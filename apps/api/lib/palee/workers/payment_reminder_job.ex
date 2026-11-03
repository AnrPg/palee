defmodule Palee.Workers.PaymentReminderJob do
  use Oban.Worker, queue: :analytics, max_attempts: 3

  alias Palee.{Finance, Notifications, Organizations}
  alias Palee.Application.DebtorContacts

  @impl Oban.Worker
  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> remind_for_organization(organization) end)

    :ok
  end

  defp remind_for_organization(organization) do
    context = %{organization_id: organization.id}
    settings = Finance.get_finance_settings(context)
    interval_days = Map.get(settings, :payment_reminder_interval_days, 7)

    # ADR-396: a deleted debtor's kept contact goes once the debt is settled.
    _released = DebtorContacts.release_settled(context)

    memberships = Finance.memberships_needing_payment_reminder(context, interval_days)

    Enum.each(memberships, fn %{
                                membership_id: membership_id,
                                user_id: user_id,
                                outstanding_balance_cents: cents
                              } = owing ->
      # A deleted profile has no app to be reminded in: its kept email is.
      case DebtorContacts.remind(context, owing, organization) do
        :no_contact ->
          Notifications.process_event("payment_reminder", %{
            user_id: user_id,
            outstanding_balance_cents: cents
          })

        _kept ->
          :ok
      end

      Finance.update_membership_reminder_timestamp(context, membership_id)
    end)
  end
end
