defmodule Palee.Application.Channels.ChannelContacts do
  @moduledoc """
  Staff › a member's or lead's card › «Τηλέφωνο για μηνύματα» (ADR-348 §4,
  ADR-350): the number, language and consent per channel. Staff record a
  consent the person gave them (source `staff`, with the consent text
  version); numbers are shown masked.
  """

  alias Palee.Channels

  @doc "The contact of `user_id` or `lead_id` (or nil): `{:ok, %{contact}}`."
  def show(context, params) do
    with {:ok, person} <- Channels.person(person_params(params)) do
      {:ok, %{contact: context |> Channels.find_contact(person) |> Channels.public_contact()}}
    end
  end

  @doc "Contacts of several people: `user_ids` / `lead_ids` (comma-separated)."
  def list(context, params) do
    filters =
      %{user_ids: ids(param(params, :user_ids)), lead_ids: ids(param(params, :lead_ids))}
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    %{
      contacts: context |> Channels.list_contacts(filters) |> Enum.map(&Channels.public_contact/1)
    }
  end

  @doc "Saves the number and language: `{:ok, %{contact}}`."
  def save(context, params) do
    with {:ok, person} <- Channels.person(person_params(params)) do
      country = default_country(context)

      with {:ok, contact} <-
             Channels.save_contact(
               context,
               person,
               %{phone: param(params, :phone), locale: param(params, :locale)}
               |> Map.reject(fn {_key, value} -> is_nil(value) end),
               country
             ) do
        {:ok, %{contact: Channels.public_contact(contact)}}
      end
    end
  end

  @doc "Grants or withdraws one consent on the person's behalf."
  def set_consent(context, contact_id, params, now \\ DateTime.utc_now()) do
    attrs = %{
      channel: param(params, :channel),
      purpose: param(params, :purpose),
      granted: param(params, :granted),
      source: param(params, :source) || "staff",
      text_version: param(params, :text_version)
    }

    with {:ok, contact} <-
           Channels.set_consent(context, contact_id, attrs, Map.get(context, :user_id), now) do
      {:ok, %{contact: Channels.public_contact(contact)}}
    end
  end

  def delete(context, contact_id), do: Channels.delete_contact(context, contact_id)

  @doc """
  For other contexts (a lead form, CP-C1/C5; an import): saves a person's
  number and the consents they gave in one go. `params`: `user_id` or
  `lead_id`, `phone`, `locale`, `consents` (`[%{channel, purpose,
  granted}]`), `source` (`form`, `import`, `person`) and `text_version`
  (the consent text shown). `{:ok, %{contact}}` or `{:error, reason}`.
  """
  def record(context, params, now \\ DateTime.utc_now()) do
    source = param(params, :source) || "form"
    consents = param(params, :consents) || []

    with true <- is_list(consents) || {:error, {:invalid_fields, %{consents: "invalid"}}},
         {:ok, %{contact: %{id: id}}} <- save(context, params) do
      Enum.reduce_while(consents, {:ok, nil}, fn consent, _acc ->
        consent_params =
          consent
          |> Map.new(fn {key, value} -> {to_string(key), value} end)
          |> Map.merge(%{"source" => source, "text_version" => param(params, :text_version)})

        case set_consent(context, id, consent_params, now) do
          {:ok, result} -> {:cont, {:ok, result}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, nil} -> show(context, params)
        other -> other
      end
    end
  end

  @doc false
  def default_country(context) do
    case Channels.connection(context) do
      %{default_country: country} -> country
      nil -> "GR"
    end
  end

  defp person_params(params),
    do:
      %{user_id: param(params, :user_id), lead_id: param(params, :lead_id)}
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

  defp ids(nil), do: nil
  defp ids(value) when is_binary(value), do: value |> String.split(",", trim: true) |> valid_ids()
  defp ids(value) when is_list(value), do: valid_ids(value)
  defp ids(_value), do: nil

  defp valid_ids(values) do
    values
    |> Enum.map(&Ecto.UUID.cast(String.trim(&1)))
    |> Enum.flat_map(fn
      {:ok, id} -> [id]
      :error -> []
    end)
    |> Enum.take(200)
  end

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
