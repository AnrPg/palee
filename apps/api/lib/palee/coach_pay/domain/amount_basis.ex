defmodule Palee.CoachPay.Domain.AmountBasis do
  @moduledoc """
  ADR-382 (product owner, 2026-11-01): whether a pay amount is `gross`
  (before the person's taxes and contributions) or `net` (after them),
  pure. Palee computes neither: the basis is what staff say the amount
  is. Every line carries one (default `gross`); a rule or a pay item sets
  the default its lines inherit, and staff may change it per line.

  Gross and net amounts are never added into one unlabelled figure:
  statements, periods and the PDF show the two subtotals side by side.
  """

  @bases ~w(gross net)

  def bases, do: @bases
  def default, do: "gross"

  @doc "Whether a value is a basis (nil is allowed where a default applies)."
  def valid?(value), do: value in @bases

  @doc """
  Whether a line departs from the `gross` default (a `net` line): the API
  marks it (`deviates_from_default`) so screens can badge it, and the PDF
  prints «Καθαρά» next to it.
  """
  def deviates?(line), do: Map.get(line, :amount_basis) == "net"

  @doc "`%{gross_cents, net_cents}` of lines (`amount_basis` missing counts as gross)."
  def subtotals(lines) do
    Enum.reduce(lines, %{gross_cents: 0, net_cents: 0}, fn line, acc ->
      case Map.get(line, :amount_basis) || "gross" do
        "net" -> %{acc | net_cents: acc.net_cents + line.amount_cents}
        _gross -> %{acc | gross_cents: acc.gross_cents + line.amount_cents}
      end
    end)
  end
end
