defmodule Palee.Repo.Migrations.SubscriptionReminderSchedule do
  @moduledoc """
  ADR-500: the box's reminder schedule for a subscription that is not renewed:
  X days before it ends (exists), on the day it ends, the day after, then
  every `payment_reminder_interval_days` until the member renews or leaves.
  The box turns the day-of and day-after reminders on or off.
  """
  use Ecto.Migration

  def change do
    alter table(:finance_settings) do
      add :subscription_end_day_reminder, :boolean, null: false, default: true
      add :subscription_day_after_reminder, :boolean, null: false, default: true
    end

    alter table(:membership_package_subscriptions) do
      add :end_day_notice_sent_at, :utc_datetime_usec
      add :renewal_followup_sent_at, :utc_datetime_usec
    end
  end
end
