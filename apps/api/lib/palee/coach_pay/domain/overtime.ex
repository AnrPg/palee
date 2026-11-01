defmodule Palee.CoachPay.Domain.Overtime do
  @moduledoc """
  ADR-382: overtime counted from the classes a person led, pure.

  For every overtime item with a `weekly_threshold` (`PayItemPolicy.computed?/1`)
  and every person holding one of its roles, the classes they led in the
  period are grouped by week (Monday to Sunday, gym-local days):

    * `per_extra_class` – classes led above the threshold that week;
    * `per_hour` – minutes led (the classes' durations) above the
      threshold × 60 that week, paid `amount × minutes ÷ 60`.

  A week the period cuts (its first or last) gets a threshold prorated by
  its days inside the period, rounded down (`threshold × days ÷ 7`), so a
  calendar month is counted the same whichever weekday it starts on.
  One line per item, person and week that has overtime.
  """

  alias Palee.CoachPay.Domain.{PayItemPolicy, Proration}

  @doc """
  Lines `[%{coach_user_id, ...}]` from `items`, the people's pay-item roles
  (`%{user_id => [role]}`), the classes (`%{coach_user_id, occurred_on,
  duration_minutes}`) and the period's dates.
  """
  def lines(items, staff_roles, classes, %Date{} = from, %Date{} = to, currency) do
    weeks = weeks_led(classes, from, to)

    for item <- items,
        PayItemPolicy.computed?(item),
        item.currency == currency,
        {user_id, by_week} <- weeks,
        PayItemPolicy.applies_to?(item, Map.get(staff_roles, user_id, [])),
        {week, led} <- Enum.sort_by(by_week, &elem(&1, 0), Date),
        line = line(item, user_id, week, led, from, to),
        line != nil do
      line
    end
  end

  defp weeks_led(classes, from, to) do
    classes
    |> Enum.filter(fn class ->
      Date.compare(class.occurred_on, from) != :lt and Date.compare(class.occurred_on, to) != :gt
    end)
    |> Enum.group_by(& &1.coach_user_id)
    |> Map.new(fn {user_id, led} ->
      {user_id, Enum.group_by(led, &Date.beginning_of_week(&1.occurred_on, :monday))}
    end)
  end

  defp line(item, user_id, week, led, from, to) do
    first = if Date.compare(week, from) == :lt, do: from, else: week
    week_end = Date.add(week, 6)
    last = if Date.compare(week_end, to) == :gt, do: to, else: week_end
    days = Date.diff(last, first) + 1

    {quantity, divisor} =
      case item.unit do
        "per_hour" ->
          minutes = led |> Enum.map(&(Map.get(&1, :duration_minutes) || 0)) |> Enum.sum()
          {minutes - div(item.weekly_threshold * 60 * days, 7), 60}

        "per_extra_class" ->
          {length(led) - div(item.weekly_threshold * days, 7), 1}
      end

    if quantity > 0 do
      %{
        coach_user_id: user_id,
        rule_id: nil,
        pay_item_id: item.id,
        kind: "overtime",
        source_type: "pay_item",
        source_id: item.id,
        occurred_on: first,
        description: String.slice(item.name, 0, 250),
        note: nil,
        quantity: quantity,
        quantity_divisor: divisor,
        unit_cents: item.amount_cents,
        base_cents: nil,
        percent_bps: nil,
        amount_cents: Proration.amount(item.amount_cents, quantity, divisor)
      }
    end
  end
end
