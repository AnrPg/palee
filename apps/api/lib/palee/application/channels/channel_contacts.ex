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

    %{contacts: context |> Channels.list_contacts(filters) |> Enum.map(&Channels.public_contact/1)}
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
