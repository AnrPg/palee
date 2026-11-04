defmodule Palee.CoachPay.Domain.Allowances do
  @moduledoc """
  ADR-510: recurring allowances added to every calculated period, pure.

  For every recurring allowance (`PayItemPolicy.recurring?/1`) in the
  period's currency and every person holding one of its roles, unless the
  allowance was taken off that person for this period (a skip):

    * `period` – one line of the amount (quantity 1);
    * `daily`, `weekly`, `monthly` – prorated by the period's calendar days
      exactly like fixed pay (`Proration.segments/3`): one line for daily
      and weekly, one per calendar month the period touches for monthly.
  """

  alias Palee.CoachPay.Domain.{PayItemPolicy, Proration}

  @doc """
  Lines `[%{coach_user_id, ...}]` from `items`, the people's pay-item roles
  (`%{user_id => [role]}`), the skipped `{user_id, pay_item_id}` pairs and
  the period's dates.
  """
  def lines(items, staff_roles, skips, %Date{} = from, %Date{} = to, currency) do
    skipped = MapSet.new(skips)

    for item <- items,
        PayItemPolicy.recurring?(item),
        is_nil(Map.get(item, :archived_at)),
        item.currency == currency,
        {user_id, roles} <- Enum.sort_by(staff_roles, &elem(&1, 0)),
        PayItemPolicy.applies_to?(item, roles),
        not MapSet.member?(skipped, {user_id, item.id}),
        segment <- segments(item, from, to) do
      line(item, user_id, segment)
    end
  end

  defp segments(%{frequency: frequency}, from, to) when frequency in ~w(daily weekly monthly),
    do: Proration.segments(%{starts_on: from, ends_on: nil, frequency: frequency}, from, to)

  defp segments(_item, from, to),
    do: [%{starts_on: from, ends_on: to, quantity: 1, divisor: 1}]

  defp line(item, user_id, segment) do
    %{
      coach_user_id: user_id,
      rule_id: nil,
      pay_item_id: item.id,
      kind: "allowance",
      source_type: "pay_item",
      source_id: item.id,
      occurred_on: segment.starts_on,
      description: String.slice(item.name, 0, 250),
      note: nil,
      quantity: segment.quantity,
      quantity_divisor: segment.divisor,
      unit_cents: item.amount_cents,
      base_cents: nil,
      percent_bps: nil,
      amount_cents: Proration.amount(item.amount_cents, segment.quantity, segment.divisor),
      amount_basis: Map.get(item, :amount_basis) || "gross"
    }
  end
end
