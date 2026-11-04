defmodule Palee.Application.DebtorContacts do
  @moduledoc """
  ADR-450: a profile deleted while it still owes a box money.

  The profile is anonymised (ADR-211) and the debt stays owed (ADR-220), so
  each box it owes keeps the least it needs to claim it (GDPR art. 17(3)(e)):
  the name, the login's email and the box's SMS number the person had. Only
  while the debt is open:

    * `keep/1` – the account-deletion sweep, before anonymising: one contact
      per membership that owes something, in that box's scope;
    * `labels/2` – staff screens show the kept name (and how to reach the
      person) instead of «Deleted account»;
    * `release_settled/1` – the box's daily run deletes the contacts of
      memberships that owe nothing any more;
    * `remind/2` – the daily payment reminder goes to the kept email, since
      the person has no account to see an in-app reminder.
  """

  alias Palee.{Channels, Email, Finance}
  alias Palee.Finance.{DebtorContactStore, FinanceStore}
  alias Palee.Identity.AccountDeletionStore

  @doc "Keeps the contact of `profile` in every box where it still owes money."
  def keep(%{id: user_id} = profile, now \\ DateTime.utc_now()) do
    user_id
    |> AccountDeletionStore.deleting_profile_memberships()
    |> Enum.group_by(& &1.organization_id, & &1.membership_id)
    |> Enum.each(fn {organization_id, membership_ids} ->
      context = %{organization_id: organization_id}

      :ok =
        Finance.with_tenant_context(context, fn ->
          keep_owing(context, profile, membership_ids, now)
        end)
    end)
  end

  defp keep_owing(context, profile, membership_ids, now) do
    balances = FinanceStore.outstanding_balance_per_membership(membership_ids)
    owing = Enum.filter(membership_ids, &(Map.get(balances, &1, 0) > 0))

    if owing != [] do
      phone = sms_number(context, profile.id)

      Enum.each(owing, fn membership_id ->
        :ok =
          DebtorContactStore.keep(%{
            organization_id: context.organization_id,
            membership_id: membership_id,
            user_id: profile.id,
            display_name: Map.get(profile, :nickname) || Map.get(profile, :handle) || "",
            email: Map.get(profile, :email),
            phone_e164: phone,
            locale: Map.get(profile, :preferred_locale) || "en",
            kept_at: now
          })
      end)
    end

    :ok
  end

  defp sms_number(context, user_id) do
    with {:ok, person} <- Channels.person(%{user_id: user_id}),
         %{phone_e164: phone} when is_binary(phone) <- Channels.find_contact(context, person) do
      phone
    else
      _none -> nil
    end
  end

  @doc """
  The kept contacts of these people in the box (`context`), by user id:
  `%{display_name, email, phone_e164}`. Staff screens put the name in place
  of «Deleted account».
  """
  def labels(context, user_ids) do
    case Enum.uniq(Enum.reject(user_ids, &is_nil/1)) do
      [] ->
        %{}

      ids ->
        Finance.with_tenant_context(context, fn ->
          ids
          |> DebtorContactStore.for_users()
          |> Map.new(fn {user_id, contact} ->
            {user_id, Map.take(contact, [:display_name, :email, :phone_e164])}
          end)
        end)
    end
  end

  @doc "Deletes the box's contacts of memberships that owe nothing any more; returns how many."
  def release_settled(context) do
    Finance.with_tenant_context(context, fn ->
      contacts = DebtorContactStore.list()

      balances =
        FinanceStore.outstanding_balance_per_membership(Enum.map(contacts, & &1.membership_id))

      contacts
      |> Enum.filter(&(Map.get(balances, &1.membership_id, 0) <= 0))
      |> Enum.map(& &1.membership_id)
      |> DebtorContactStore.release()
    end)
  end

  @doc """
  The payment reminder of a membership whose profile was deleted: an email
  (`:debt_reminder`) to the kept address. `:emailed`, `:kept_without_email`
  (the box has only the name or number), or `:no_contact` when the profile
  was not deleted, so the caller reminds in the app as usual.
  """
  def remind(context, %{membership_id: membership_id, outstanding_balance_cents: cents}, box) do
    contact =
      Finance.with_tenant_context(context, fn ->
        Enum.find(DebtorContactStore.list(), &(&1.membership_id == membership_id))
      end)

    case contact do
      %{email: email} = contact when is_binary(email) and email != "" ->
        _sent =
          Email.enqueue(
            :debt_reminder,
            email,
            %{box: box.name, amount_cents: cents, currency: "EUR"},
            locale: contact.locale,
            organization_id: context.organization_id,
            idempotency_key: "debt_reminder:#{membership_id}:#{Date.utc_today()}"
          )

        :emailed

      %{} ->
        :kept_without_email

      nil ->
        :no_contact
    end
  end
end
