defmodule Palee.CoachPay.Domain.Proration do
  @moduledoc """
  ADR-382: fixed pay prorated by calendar days, and the rounding every
  divided amount follows, pure.

  A line's amount is `unit_cents × quantity ÷ quantity_divisor`, in integer
  cents, rounded half away from zero (`amount/3`), once per line:

    * `daily` – one line: quantity = the days the rule is valid in the
      period, divisor 1 (exact);
    * `weekly` – one line: quantity = those days, divisor 7;
    * `monthly` – one line per calendar month the period touches:
      quantity = the days the rule is valid in that month (inside the
      period), divisor = the days of that month. A full month pays the
      amount exactly; a part month pays its share of that month.

  Dates are gym-local calendar days (periods and rules are stored as
  gym-local dates, ADR-176/179), so a day is a day of the box's time zone.
  """

  @doc "`unit × quantity ÷ divisor` in cents, rounded half away from zero."
  def amount(unit_cents, quantity, divisor \\ 1)
      when is_integer(unit_cents) and is_integer(quantity) and is_integer(divisor) and
             divisor > 0 do
    raw = unit_cents * quantity

    if raw >= 0,
      do: div(2 * raw + divisor, 2 * divisor),
      else: -div(-2 * raw + divisor, 2 * divisor)
  end

  @doc """
  The segments a fixed rule pays for inside `[from, to]` (the period):
  `[%{starts_on, ends_on, quantity, divisor}]`, empty when the rule is not
  valid on any day of the period.
  """
  def segments(rule, %Date{} = from, %Date{} = to) do
    case overlap(rule, from, to) do
      nil -> []
      {first, last} -> split(rule.frequency, first, last)
    end
  end

  defp overlap(rule, from, to) do
    first = later(rule.starts_on, from)
    last = if rule.ends_on, do: earlier(rule.ends_on, to), else: to

    if Date.compare(first, last) == :gt, do: nil, else: {first, last}
  end

  defp split("daily", first, last), do: [segment(first, last, 1)]
  defp split("weekly", first, last), do: [segment(first, last, 7)]

  defp split("monthly", first, last) do
    first
    |> Stream.unfold(fn
      nil ->
        nil

      start ->
        month_end = Date.end_of_month(start)
        stop = earlier(month_end, last)
        next = if Date.compare(stop, last) == :lt, do: Date.add(stop, 1)
        {segment(start, stop, Date.days_in_month(start)), next}
    end)
    |> Enum.to_list()
  end

  defp segment(first, last, divisor),
    do: %{
      starts_on: first,
      ends_on: last,
      quantity: Date.diff(last, first) + 1,
      divisor: divisor
    }

  defp later(a, b), do: if(Date.compare(a, b) == :lt, do: b, else: a)
  defp earlier(a, b), do: if(Date.compare(a, b) == :gt, do: b, else: a)
end
