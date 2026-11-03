defmodule Palee.Integrations.Domain.AudienceSyncPlan do
  @moduledoc """
  What one Mailchimp/Brevo sync does (ADR-380). Only members who said yes
  to the box's marketing email, and have not taken it back, are sent; that
  is the whole consent rule, and it is checked here, not in the adapters.

  Each contact carries the email and first name only (data minimisation):
  no phone, birthday, package or attendance. A member who withdraws, leaves
  the box or deletes the account is unsubscribed in the list (never deleted
  there: the provider must keep the address to honour the unsubscribe).

  Pure: given the members wanting email now and what the list already has,
  `plan/2` answers `%{subscribe: [contact], unsubscribe: [audience_member]}`.
  """

  @type contact :: %{user_id: String.t(), email: String.t(), first_name: String.t() | nil}

  @doc """
  `wanted`: contacts with consent now. `synced`: the box's `audience_members`
  rows (`user_id`, `email_hash`, `status`).
  """
  def plan(wanted, synced) when is_list(wanted) and is_list(synced) do
    synced_by_user = Map.new(synced, &{&1.user_id, &1})
    wanted_ids = MapSet.new(wanted, & &1.user_id)

    subscribe =
      Enum.filter(wanted, fn contact ->
        case Map.get(synced_by_user, contact.user_id) do
          %{status: "subscribed", email_hash: hash} -> hash != email_hash(contact.email)
          _missing_or_unsubscribed -> true
        end
      end)

    unsubscribe =
      Enum.filter(synced, fn row ->
        row.status == "subscribed" and not MapSet.member?(wanted_ids, row.user_id)
      end)

    %{subscribe: subscribe, unsubscribe: unsubscribe}
  end

  @doc "Lower-case trimmed email."
  def normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  @doc "Hex SHA-256 of the normalized email (what Palee remembers per member)."
  def email_hash(email),
    do: :sha256 |> :crypto.hash(normalize_email(email)) |> Base.encode16(case: :lower)

  @doc "Mailchimp's subscriber hash: hex MD5 of the lower-case email."
  def mailchimp_subscriber_hash(email),
    do: :md5 |> :crypto.hash(normalize_email(email)) |> Base.encode16(case: :lower)

  @doc "The first word of a display name, as the list's first-name field."
  def first_name(nil), do: nil

  def first_name(name) when is_binary(name) do
    case String.split(String.trim(name), ~r/\s+/, parts: 2) do
      [""] -> nil
      [first | _rest] -> String.slice(first, 0, 50)
    end
  end
end
