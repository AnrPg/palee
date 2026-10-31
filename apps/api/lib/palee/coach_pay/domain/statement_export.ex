defmodule Palee.CoachPay.Domain.StatementExport do
  @moduledoc """
  CP-A6 (ADR-341): the period's statements as CSV for the accountant,
  pure. One row per line, with the coach, the period and the source, so
  the accountant can tie every amount to the class, session or payment
  behind it. Amounts are decimal with two places, in the period's currency.
  Cells that would start a spreadsheet formula are quoted harmless.
  """

  @header ~w(period_start period_end coach coach_id date kind description quantity unit
             base percent amount currency source_type source_id)

  def csv(period, statements, names) do
    rows =
      for statement <- statements, line <- statement.lines do
        [
          Date.to_iso8601(period.starts_on),
          Date.to_iso8601(period.ends_on),
          Map.get(names, statement.coach_user_id, ""),
          statement.coach_user_id,
          Date.to_iso8601(line.occurred_on),
          line.kind,
          line.description,
          Integer.to_string(line.quantity || 1),
          money(line.unit_cents),
          money(line.base_cents),
          percent(line.percent_bps),
          money(line.amount_cents),
          period.currency,
          line.source_type,
          line.source_id || ""
        ]
      end

    [@header | rows]
    |> Enum.map_join("\r\n", fn row -> Enum.map_join(row, ",", &cell/1) end)
    |> Kernel.<>("\r\n")
  end

  @doc "Totals per coach for the summary rows."
  def money(nil), do: ""

  def money(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    abs = abs(cents)

    "#{sign}#{div(abs, 100)}.#{abs |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp percent(nil), do: ""
  defp percent(bps), do: money(bps)

  defp cell(value) do
    value = to_string(value)

    value =
      if String.starts_with?(value, ["=", "+", "@", "\t", "\r"]) or
           (String.starts_with?(value, "-") and not String.match?(value, ~r/^-\d+(\.\d+)?$/)),
         do: "'" <> value,
         else: value

    if String.contains?(value, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(value, "\"", "\"\"") <> "\"",
      else: value
  end
end
