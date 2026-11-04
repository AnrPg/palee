defmodule Palee.CoachPay.Domain.StatementGroups do
  @moduledoc """
  ADR-382: a statement's lines as one group per rule (and per pay item,
  and one for each kind of line added by hand, ADR-510: one-off overtime and
  allowances included), with the terms they were
  paid by, the quantity × rate and the group's total, pure.

  A rule's clawbacks fall in that rule's group, so the group shows what the
  rule paid after refunds. Lines of one rule with different amount bases
  (`gross`, `net`) form separate groups: they are never summed together.
  Groups come in a fixed order: rules (by kind), overtime, allowances,
  payments by hand, reimbursements, adjustments.
  """

  @order ~w(fixed per_class per_attendee per_session percent_of_sales overtime allowance
            ad_hoc non_taxable_reimbursement adjustment)

  @doc """
  `[%{key, kind, rule_id, pay_item_id, amount_basis, terms, line_count, quantity,
  quantity_divisor, unit_cents, base_cents, amount_cents}]`. `unit_cents`
  and `quantity_divisor` are nil when the group's lines differ in them;
  `quantity` sums the lines' quantities (minutes for hourly overtime,
  days for fixed pay, attendees, classes, ...).
  """
  def groups(%{lines: lines} = statement) do
    terms = Map.get(statement, :rule_terms) || %{}

    lines
    |> Enum.group_by(&(key(&1) <> ":" <> basis(&1)))
    |> Enum.map(fn {key, lines} -> group(key, lines, terms) end)
    |> Enum.sort_by(&{rank(&1.kind), &1.key})
  end

  defp basis(line), do: Map.get(line, :amount_basis) || "gross"

  # Lines added by hand group by kind, apart from what was calculated (one-off
  # overtime and allowances too, ADR-510), so each can be read and removed.
  defp key(%{source_type: "manual", kind: kind}), do: "manual:" <> kind
  defp key(%{rule_id: rule_id}) when is_binary(rule_id), do: "rule:" <> rule_id

  defp key(%{pay_item_id: item_id, kind: kind}) when is_binary(item_id),
    do: "pay_item:" <> item_id <> ":" <> kind

  defp key(%{kind: kind}), do: "manual:" <> kind

  defp group(key, [first | _] = lines, terms) do
    id = first.rule_id || Map.get(first, :pay_item_id)
    kind = group_kind(first)
    paid = Enum.reject(lines, &(&1.kind == "clawback"))

    %{
      key: key,
      kind: kind,
      rule_id: first.rule_id,
      pay_item_id: Map.get(first, :pay_item_id),
      amount_basis: basis(first),
      terms: id && Map.get(terms, id),
      line_count: length(lines),
      quantity: lines |> Enum.map(&(&1.quantity || 0)) |> Enum.sum(),
      quantity_divisor: same(paid, &Map.get(&1, :quantity_divisor)),
      unit_cents: same(paid, & &1.unit_cents),
      base_cents: sum_or_nil(lines, & &1.base_cents),
      amount_cents: lines |> Enum.map(& &1.amount_cents) |> Enum.sum()
    }
  end

  defp group_kind(%{kind: "clawback"}), do: "percent_of_sales"
  defp group_kind(%{kind: kind}), do: kind

  defp same([], _fun), do: nil

  defp same(lines, fun) do
    case lines |> Enum.map(fun) |> Enum.uniq() do
      [value] -> value
      _many -> nil
    end
  end

  defp sum_or_nil(lines, fun) do
    case lines |> Enum.map(fun) |> Enum.reject(&is_nil/1) do
      [] -> nil
      values -> Enum.sum(values)
    end
  end

  defp rank(kind), do: Enum.find_index(@order, &(&1 == kind)) || length(@order)
end
