defmodule Palee.CoachPay.Domain.PayCalculator do
  @moduledoc """
  CP-A6 (ADR-341): a period's pay lines from the coaches' rules and the
  work and money of the period, pure.

  `work` (read through `Palee.CoachPay.Ports.WorkSource`, dates gym-local):

    * `classes` – `%{class_id, coach_user_id, class_type_id, name,
      occurred_on, attendance: %{"attended" => n, ...}}`;
    * `sessions` – `%{slot_id, coach_user_id, kind, occurred_on,
      bookings: %{"attended" => n, ...}}`;
    * `sales` – `%{kind: "payment" | "reversal", id, occurred_on,
      amount_cents, currency, package_name, pt_coach_id, sold_by_id}`.

  Every line names its rule and its source, so a statement can be traced
  to the class, session, payment or refund behind it. A rule in another
  currency than the money is skipped (never converted).
  """

  alias Palee.CoachPay.Domain.RulePolicy

  @doc "Lines per coach: `%{coach_user_id => [line]}` (coaches with no line left out)."
  def calculate(rules, work, currency) do
    rules
    |> Enum.filter(&(&1.currency == currency))
    |> Enum.flat_map(&lines(&1, work))
    |> Enum.group_by(& &1.coach_user_id, &Map.delete(&1, :coach_user_id))
  end

  defp lines(%{kind: "per_class"} = rule, work) do
    for class <- coach_classes(rule, work),
        count = counted(rule, class.attendance),
        count >= rule.min_attendees do
      line(rule, "scheduled_class", class.class_id, class.occurred_on, class.name, %{
        quantity: 1,
        unit_cents: rule.amount_cents,
        amount_cents: rule.amount_cents
      })
    end
  end

  defp lines(%{kind: "per_attendee"} = rule, work) do
    for class <- coach_classes(rule, work),
        count = counted(rule, class.attendance),
        count >= max(rule.min_attendees, 1) do
      paid = if is_integer(rule.max_attendees), do: min(count, rule.max_attendees), else: count

      line(rule, "scheduled_class", class.class_id, class.occurred_on, class.name, %{
        quantity: paid,
        unit_cents: rule.amount_cents,
        amount_cents: paid * rule.amount_cents
      })
    end
  end

  defp lines(%{kind: "per_session"} = rule, work) do
    for session <- Map.get(work, :sessions, []),
        session.coach_user_id == rule.coach_user_id,
        RulePolicy.active_on?(rule, session.occurred_on),
        Map.get(session.bookings, "attended", 0) > 0 do
      line(rule, "appointment_slot", session.slot_id, session.occurred_on, session.kind, %{
        quantity: 1,
        unit_cents: rule.amount_cents,
        amount_cents: rule.amount_cents
      })
    end
  end

  defp lines(%{kind: "percent_of_sales"} = rule, work) do
    for sale <- Map.get(work, :sales, []),
        sale.currency == rule.currency,
        attributed?(rule, sale),
        RulePolicy.active_on?(rule, sale.occurred_on),
        amount = share(sale.amount_cents, rule.percent_bps),
        amount != 0 do
      {kind, source} =
        if sale.kind == "reversal",
          do: {"clawback", "finance_reversal"},
          else: {"percent_of_sales", "finance_payment"}

      rule
      |> line(source, sale.id, sale.occurred_on, sale.package_name || "", %{
        quantity: 1,
        base_cents: sale.amount_cents,
        percent_bps: rule.percent_bps,
        amount_cents: amount
      })
      |> Map.put(:kind, kind)
    end
  end

  defp coach_classes(rule, work) do
    Enum.filter(Map.get(work, :classes, []), fn class ->
      class.coach_user_id == rule.coach_user_id and RulePolicy.active_on?(rule, class.occurred_on) and
        (rule.class_type_ids == [] or class.class_type_id in rule.class_type_ids)
    end)
  end

  defp counted(rule, attendance),
    do: rule.count_statuses |> Enum.map(&Map.get(attendance, &1, 0)) |> Enum.sum()

  defp attributed?(%{sales_scope: "personal_training"} = rule, sale),
    do: sale.pt_coach_id == rule.coach_user_id

  defp attributed?(%{sales_scope: "sold_by"} = rule, sale),
    do: sale.sold_by_id == rule.coach_user_id

  defp attributed?(_rule, _sale), do: false

  @doc "A percent (basis points) of an amount, rounded half away from zero."
  def share(amount_cents, bps) do
    raw = amount_cents * bps

    if raw >= 0,
      do: div(raw + 5_000, 10_000),
      else: -div(-raw + 5_000, 10_000)
  end

  defp line(rule, source_type, source_id, occurred_on, description, amounts) do
    Map.merge(
      %{
        coach_user_id: rule.coach_user_id,
        rule_id: rule.id,
        kind: rule.kind,
        source_type: source_type,
        source_id: source_id,
        occurred_on: occurred_on,
        description: description |> to_string() |> String.slice(0, 250),
        quantity: 1,
        unit_cents: nil,
        base_cents: nil,
        percent_bps: nil
      },
      amounts
    )
  end

  @doc "A statement's total."
  def total(lines), do: lines |> Enum.map(& &1.amount_cents) |> Enum.sum()
end
