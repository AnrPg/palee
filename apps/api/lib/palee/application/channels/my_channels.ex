defmodule Palee.Application.Channels.MyChannels do
  @moduledoc """
  The member's own «Μηνύματα από το box» (ADR-350): their number for this
  box, their language and which channels they agree to, for what. The
  member sees their full number; consents they give carry source
  `person` and the consent text version the app showed.
  """

  alias Palee.Application.Channels.ChannelContacts
  alias Palee.Channels

  def show(%{user_id: user_id} = context) do
    contact = Channels.find_contact(context, {:user, user_id})

    %{
      contact: Channels.own_contact(contact),
      channels: enabled_channels(context)
    }
  end

  @doc """
  Saves the number and language and any `consents` (`[%{channel, purpose,
  granted}]`) in one go, all with the same `text_version`.
  """
  def save(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    country = ChannelContacts.default_country(context)
    consents = param(params, :consents) || []

    contact_params =
      %{phone: param(params, :phone), locale: param(params, :locale)}
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    with :ok <- valid_consents(consents),
         {:ok, contact} <- Channels.save_contact(context, {:user, user_id}, contact_params, country),
         {:ok, contact} <- apply_consents(context, contact, consents, param(params, :text_version), now) do
      {:ok, %{contact: Channels.own_contact(contact), channels: enabled_channels(context)}}
    end
  end

  defp valid_consents(consents) when is_list(consents) and length(consents) <= 6, do: :ok
  defp valid_consents(_consents), do: {:error, {:invalid_fields, %{consents: "invalid"}}}

  defp apply_consents(_context, contact, [], _version, _now), do: {:ok, contact}

  defp apply_consents(context, contact, consents, version, now) do
    Enum.reduce_while(consents, {:ok, contact}, fn consent, _acc ->
      attrs = %{
        channel: param(consent, :channel),
        purpose: param(consent, :purpose),
        granted: param(consent, :granted),
        source: "person",
        text_version: version
      }

      case Channels.set_consent(context, contact.id, attrs, context.user_id, now) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        error -> {:halt, error}
      end
    end)
  end

  defp enabled_channels(context) do
    case Channels.connection(context) do
      %{channels: channels} -> channels
      nil -> []
    end
  end

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp param(_params, _key), do: nil
end
