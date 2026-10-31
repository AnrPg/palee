defmodule Palee.Channels.Contacts do
  @moduledoc """
  People the box may text (ADR-348 §4, ADR-350): a member (`user_id`) or a
  lead (`lead_id`, CP-C1), their mobile in E.164, their language, and their
  consent per channel and purpose.

  Consent is opt-in and specific: nothing is assumed from a member's
  contract or a lead's form unless the person ticked that channel and
  purpose (the form or import records it with its text version). A STOP
  reply withdraws every consent of every contact with that number in the
  box and marks them opted out; only the person (or staff on their
  explicit request) grants it again.
  """

  alias Palee.Channels.ChannelStore
  alias Palee.Channels.Domain.{ChannelPolicy, PhoneNumber}

  @locales ~w(el en de fr it es nl pt-PT bg ru ar he)

  def locales, do: @locales

  @doc "`{:user, id}` / `{:lead, id}` from `%{user_id}` or `%{lead_id}`."
  def person(%{user_id: id}) when is_binary(id), do: cast_person(:user, id)
  def person(%{lead_id: id}) when is_binary(id), do: cast_person(:lead, id)
  def person(_params), do: {:error, :channel_person_required}

  defp cast_person(kind, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, {kind, id}}
      :error -> {:error, :channel_person_required}
    end
  end

  @doc "The contact of a person with its consents, or nil."
  def find(context, person) do
    case ChannelStore.find_contact(context, person) do
      nil -> nil
      contact -> with_consents(context, contact)
    end
  end

  @doc "A contact by id with its consents, or nil."
  def get(context, id) do
    case ChannelStore.get_contact(context, id) do
      nil -> nil
      contact -> with_consents(context, contact)
    end
  end

  @doc "Contacts of many people (filters `user_ids`, `lead_ids`, `limit`) with consents."
  def list(context, filters) do
    contacts = ChannelStore.list_contacts(context, filters)
    consents = ChannelStore.list_consents(context, Enum.map(contacts, & &1.id))
    grouped = Enum.group_by(consents, & &1.contact_id)
    Enum.map(contacts, &Map.put(&1, :consents, Map.get(grouped, &1.id, [])))
  end

  defp with_consents(context, contact),
    do: Map.put(contact, :consents, ChannelStore.list_consents(context, [contact.id]))

  @doc """
  Saves a person's number and language. `params`: `phone` (any common
  form; E.164 after normalisation with the box's country), `locale`.
  `{:ok, contact}` or `{:error, {:invalid_fields, errors}}`.
  """
  def save(context, person, params, default_country) do
    existing = ChannelStore.find_contact(context, person)
    phone_param = params[:phone]
    locale = params[:locale] || (existing && existing.locale) || "el"

    phone =
      cond do
        is_binary(phone_param) -> PhoneNumber.normalize(phone_param, default_country)
        existing -> {:ok, existing.phone_e164}
        true -> {:error, :invalid_phone}
      end

    errors =
      %{}
      |> add(match?({:error, _}, phone), :phone, "invalid")
      |> add(locale not in @locales, :locale, "invalid")

    if errors == %{} do
      {:ok, e164} = phone

      with {:ok, contact} <-
             ChannelStore.save_contact(context, person, %{phone_e164: e164, locale: locale}) do
        {:ok, with_consents(context, contact)}
      end
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  @doc """
  Grants or withdraws one consent. `params`: `channel`, `purpose`,
  `granted` (boolean), `source` (`person`, `staff`, `form`, `import`),
  `text_version` (the consent text shown). Granting clears a STOP.
  """
  def set_consent(context, contact_id, params, actor_id, %DateTime{} = now) do
    channel = params[:channel]
    purpose = params[:purpose]
    source = params[:source] || "staff"

    errors =
      %{}
      |> add(channel not in ChannelPolicy.channels(), :channel, "invalid")
      |> add(purpose not in ChannelPolicy.purposes(), :purpose, "invalid")
      |> add(not is_boolean(params[:granted]), :granted, "invalid")
      |> add(source not in ~w(person staff form import), :source, "invalid")
      |> add(
        is_binary(params[:text_version]) and String.length(params[:text_version]) > 40,
        :text_version,
        "too_long"
      )

    cond do
      errors != %{} ->
        {:error, {:invalid_fields, errors}}

      is_nil(ChannelStore.get_contact(context, contact_id)) ->
        {:error, :not_found}

      true ->
        change =
          if params[:granted],
            do: %{granted_at: now, text_version: params[:text_version]},
            else: %{withdrawn_at: now}

        ChannelStore.transaction(context, fn ->
          with {:ok, _consent} <-
                 ChannelStore.put_consent(
                   context,
                   contact_id,
                   channel,
                   purpose,
                   Map.merge(change, %{source: source, recorded_by_id: actor_id})
                 ),
               {:ok, _contact} <- clear_stop(context, contact_id, params[:granted]) do
            {:ok, get(context, contact_id)}
          end
        end)
    end
  end

  defp clear_stop(context, contact_id, true) do
    contact = ChannelStore.get_contact(context, contact_id)

    ChannelStore.save_contact(context, person_of(contact), %{opted_out_at: nil})
  end

  defp clear_stop(_context, _contact_id, _granted), do: {:ok, nil}

  defp person_of(%{user_id: id}) when is_binary(id), do: {:user, id}
  defp person_of(%{lead_id: id}), do: {:lead, id}

  @doc "Deletes a contact with its consents and messages (the person's request)."
  def delete(context, id) do
    case ChannelStore.get_contact(context, id) do
      nil -> {:error, :not_found}
      _contact -> ChannelStore.delete_contact(context, id)
    end
  end

  @doc """
  A STOP reply from `phone`: every contact with that number stops
  (consents withdrawn with source `stop_keyword`). Answers how many
  contacts it stopped.
  """
  def stop(context, phone, %DateTime{} = now) do
    contacts = ChannelStore.contacts_by_phone(context, phone)
    consents = ChannelStore.list_consents(context, Enum.map(contacts, & &1.id))

    ChannelStore.transaction(context, fn ->
      Enum.each(consents, fn consent ->
        {:ok, _consent} =
          ChannelStore.put_consent(context, consent.contact_id, consent.channel, consent.purpose, %{
            withdrawn_at: now,
            source: "stop_keyword"
          })
      end)

      Enum.each(contacts, fn contact ->
        {:ok, _contact} = ChannelStore.save_contact(context, person_of(contact), %{opted_out_at: now})
      end)

      {:ok, length(contacts)}
    end)
  end

  @doc "Whether the person has a current consent for `channel` and `purpose`."
  def consented?(context, person, channel, purpose) do
    case find(context, person) do
      nil -> false
      %{opted_out_at: %DateTime{}} -> false
      contact -> ChannelPolicy.consented?(contact.consents, channel, purpose)
    end
  end

  @doc "A contact as staff see it: the number masked, consents per channel."
  def public(nil), do: nil

  def public(contact) do
    %{
      id: contact.id,
      user_id: contact.user_id,
      lead_id: contact.lead_id,
      phone: PhoneNumber.mask(contact.phone_e164),
      country: PhoneNumber.country(contact.phone_e164),
      locale: contact.locale,
      opted_out_at: contact.opted_out_at,
      consents:
        for channel <- ChannelPolicy.channels(), purpose <- ChannelPolicy.purposes() do
          consent =
            Enum.find(contact.consents, &(&1.channel == channel and &1.purpose == purpose))

          %{
            channel: channel,
            purpose: purpose,
            granted: not is_nil(consent) and ChannelPolicy.granted?(consent),
            granted_at: consent && consent.granted_at,
            withdrawn_at: consent && consent.withdrawn_at,
            source: consent && consent.source,
            text_version: consent && consent.text_version
          }
        end,
      updated_at: contact.updated_at
    }
  end

  @doc "The person's own view: their full number (it is theirs)."
  def own(nil), do: nil
  def own(contact), do: contact |> public() |> Map.put(:phone, contact.phone_e164)

  defp add(errors, true, field, code), do: Map.put_new(errors, field, code)
  defp add(errors, false, _field, _code), do: errors
end
