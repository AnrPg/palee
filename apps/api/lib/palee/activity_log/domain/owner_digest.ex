defmodule Palee.ActivityLog.Domain.OwnerDigest do
  @moduledoc """
  ADR-760 (ANR 12B): the owner's morning summary of the box's sensitive
  actions of the day before (`Actions.sensitive?/1`), on the box's own
  clock (ADR-176). Pure: which day a run covers, its window, the counts per
  kind of action and the link to «Αρχείο ενεργειών».

  It goes out from 07:00 on the box's clock, the morning hour the staff's
  other box-day notices use (`ClassWorkoutReadiness`: the 07:00 alert for a
  class without its WOD). Before 07:00 a run covers nothing; any run after
  it covers yesterday, so an hour the job missed is caught up later the
  same day, and the notification's dedupe key keeps it to one a day.
  """

  alias Palee.ActivityLog.Domain.Actions
  alias Palee.TimeZones.ZonedTime

  @send_hour 7

  # The kind's words in the `activity_log` gettext domain. Every sensitive
  # key has one (a test keeps it so); a key without one is counted under
  # «Άλλες ευαίσθητες ενέργειες».
  @labels %{
    "member.remove" => "Box members removed",
    "member.role_change" => "Role changes",
    "member.status_set" => "Statuses set by hand",
    "member.status_reset" => "Statuses back to automatic",
    "role_access.change" => "Role permission changes",
    "import.apply" => "Imports applied",
    "import.undo" => "Imports undone",
    "payment.reverse" => "Payments reversed",
    "payment.refund" => "Refunds",
    "payment.charge_dismiss" => "Failed charges closed",
    "payment_account.save" => "Payment account changes",
    "payment_account.connect" => "Payment accounts connected",
    "payment_account.disconnect" => "Payment accounts disconnected",
    "invoice.void" => "Invoices voided",
    "credit.create" => "Credits given",
    "credit.reverse" => "Credits reversed",
    "benefit.give" => "Gifts to box members",
    "benefit.revoke" => "Gifts taken back",
    "corporate.payment_reverse" => "Company payments reversed",
    "finance_record.purge" => "Financial records deleted",
    "fiscal.credit_note" => "Credit notes",
    "fiscal.connection_save" => "Fiscal connection changes",
    "package.remove" => "Subscription packages removed",
    "package.end_set" => "Subscription package end dates set by hand",
    "package.end_reset" => "Subscription package end dates reset",
    "package_request.activate_unpaid" => "Subscription packages activated before payment",
    "door.unlock" => "Doors opened remotely",
    "shop.order_refund" => "Shop order refunds",
    "programme.refund" => "Programme refunds",
    "pay_period.reopen" => "Pay periods reopened",
    "organization.transfer" => "Ownership transfers",
    "organization.archive" => "Box archived",
    "data_export.create" => "Data exports",
    "integration.key_create" => "API keys created",
    "integration.key_rotate" => "API keys renewed",
    "integration.key_revoke" => "API keys revoked"
  }

  @other "other"
  @other_label "Other sensitive actions"

  def send_hour, do: @send_hour

  @doc "Every kind's words (the gettext msgids), for the catalogue check."
  def labels, do: @labels

  @doc "The words of a kind (`\"other\"` and unknown keys: the catch-all)."
  def label(key), do: Map.get(@labels, key, @other_label)

  @doc """
  The box day a run at `now` covers: `{:ok, day}` (yesterday on the box's
  clock) once its morning hour came, else `:not_yet`.
  """
  def due_day(%DateTime{} = now, zone) do
    local = ZonedTime.local(now, zone)

    if local.hour >= @send_hour,
      do: {:ok, local |> DateTime.to_date() |> Date.add(-1)},
      else: :not_yet
  end

  @doc "The UTC window `[from, to)` of a box day."
  def window(%Date{} = day, zone),
    do: {ZonedTime.start_of_day(day, zone), ZonedTime.start_of_day(Date.add(day, 1), zone)}

  @doc """
  The counts per kind of the sensitive `entries` (maps with `action`), the
  most frequent first: `[%{action, count}]`. Rows of keys that are no longer
  sensitive are left out; sensitive keys without words are one `"other"`.
  """
  def counts(entries) do
    entries
    |> Enum.map(&Map.get(&1, :action))
    |> Enum.filter(&(is_binary(&1) and Actions.sensitive?(&1)))
    |> Enum.map(&if(Map.has_key?(@labels, &1), do: &1, else: @other))
    |> Enum.frequencies()
    |> Enum.map(fn {action, count} -> %{action: action, count: count} end)
    |> Enum.sort_by(&{&1.action == @other, -&1.count, &1.action})
  end

  @doc "The total of `counts/1`."
  def total(counts), do: counts |> Enum.map(& &1.count) |> Enum.sum()

  @doc "«Αρχείο ενεργειών» on the sensitive rows of that day (box days, `to` included)."
  def path(%Date{} = day) do
    date = Date.to_iso8601(day)
    "/admin/activity-log?" <> URI.encode_query(sensitive: "1", from: date, to: date)
  end

  @doc "Notification dedupe key and email idempotency stem: one per box and day."
  def key(organization_id, %Date{} = day),
    do: "activity_log_digest:#{organization_id}:#{Date.to_iso8601(day)}"
end
