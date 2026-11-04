defmodule Palee.Workers.SubscriptionExpiryJob do
  @moduledoc """
  Daily: tells clients about their subscription ending, and keeps entitlement
  snapshots in step with the calendar.

  The box's reminder schedule for a subscription that is not renewed
  (ADR-500; every step is a finance setting):

    * `subscription_expiring` – once, `subscription_expiry_reminder_days`
      before it ends, and (`subscription_end_day_reminder`) once on the day
      it ends (`days_left: 0`);
    * `subscription_grace` – (`subscription_day_after_reminder`) once on the
      day after it ended; `grace_until` is set while the member is in the
      `subscription_grace_days` slack (they keep access until it is over,
      then lose it, e.g. they can no longer book classes);
    * `subscription_grace` again (`followup: true`) every
      `payment_reminder_interval_days` after that, until the member renews
      or leaves; a member who owes money gets the payment reminder instead;
    * `access_ended` – when the slack is over (or a payment stays overdue past
      it) the client loses every entitlement: new bookings, starting workouts,
      assignments and coaching touchpoints are refused by `EntitlementPolicy`,
      and their upcoming class bookings are cancelled here (the places and
      class allowances are released).

  Notifications go to the client (in-app and push, in their language).
  """
  use Oban.Worker, queue: :analytics, max_attempts: 3

  alias Palee.{Finance, Notifications, Organizations}
  alias Palee.Application.RevokeAccess
  alias Palee.Finance.Domain.InvoiceLifecycle

  @impl Oban.Worker
  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> run(%{organization_id: organization.id}) end)

    :ok
  end

  @doc "Runs the job for one organization (`context` carries its id)."
  def run(context, today \\ nil) do
    today = today || Organizations.local_today(context.organization_id)
    settings = Finance.get_finance_settings(context)
    reminder_days = Map.get(settings, :subscription_expiry_reminder_days, 5) || 0
    grace_days = Map.get(settings, :subscription_grace_days, 3) || 0
    end_day? = Map.get(settings, :subscription_end_day_reminder, true) != false
    day_after? = Map.get(settings, :subscription_day_after_reminder, true) != false
    interval = Map.get(settings, :payment_reminder_interval_days, 7) || 7

    context
    |> Finance.subscriptions_needing_expiry_notice(:expiry_reminder, %{
      days: reminder_days,
      skip_end_day: end_day?
    })
    |> Enum.each(fn subscription ->
      notify(context, subscription, "subscription_expiring", :expiry_reminder, %{
        days_left: Date.diff(subscription.ends_on, today),
        grace_days: grace_days
      })
    end)

    if end_day? do
      context
      |> Finance.subscriptions_needing_expiry_notice(:end_day, %{})
      |> Enum.each(fn subscription ->
        notify(context, subscription, "subscription_expiring", :end_day, %{
          days_left: 0,
          grace_days: grace_days
        })
      end)
    end

    if day_after? do
      context
      |> Finance.subscriptions_needing_expiry_notice(:grace_notice, %{lookback: grace_days})
      |> Enum.each(fn subscription ->
        notify(context, subscription, "subscription_grace", :grace_notice, %{
          grace_until: grace_until(subscription.ends_on, grace_days, today)
        })
      end)
    end

    context
    |> Finance.subscriptions_needing_expiry_notice(:renewal_followup, %{interval: interval})
    |> Enum.each(fn subscription ->
      notify(context, subscription, "subscription_grace", :renewal_followup, %{
        grace_until: grace_until(subscription.ends_on, grace_days, today),
        followup: true
      })
    end)

    context
    |> Finance.refresh_entitlement_snapshots()
    |> Enum.each(&RevokeAccess.call(context, &1))

    :ok
  end

  # The last day of access while the member is still in the slack; nil after.
  defp grace_until(ends_on, grace_days, today) do
    until = InvoiceLifecycle.grace_until(ends_on, grace_days)

    if grace_days > 0 and Date.compare(until, today) != :lt,
      do: Date.to_iso8601(until),
      else: nil
  end

  defp notify(context, subscription, event, kind, extra) do
    payload =
      Map.merge(extra, %{
        user_id: subscription.user_id,
        subscription_id: subscription.subscription_id,
        package_name: subscription.package_name,
        ends_on: Date.to_iso8601(subscription.ends_on),
        notice: kind
      })

    case Notifications.process_event(event, payload) do
      :ok -> Finance.mark_subscription_notice_sent(context, subscription.subscription_id, kind)
      _failed -> :ok
    end
  end
end
