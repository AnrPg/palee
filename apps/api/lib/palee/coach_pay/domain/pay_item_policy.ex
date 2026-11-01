defmodule Palee.CoachPay.Domain.PayItemPolicy do
  @moduledoc """
  ADR-382: the box's catalogue of overtime and allowances, pure.

    * `overtime` – `amount_cents` `per_hour` or `per_extra_class`. With a
      `weekly_threshold` (hours or classes a week) it is counted from the
      classes the person led (`Palee.CoachPay.Domain.Overtime`); without
      one (nil, the default) staff add it to a period by hand.
    * `allowance` – `amount_cents` `per_period` (once a period) or
      `per_occurrence` (times the number of occurrences); always added to
      a period by hand, per person.

  `roles` are the box's roles the item applies to: `owner`, `admin`,
  `head_coach` (a coach who coaches every client), `coach`, `front_desk`,
  `accountant`, `janitor`. A head coach also holds `coach`.
  """

  alias Palee.CoachPay.Domain.Proration

  @kinds ~w(overtime allowance)
  @units %{"overtime" => ~w(per_hour per_extra_class), "allowance" => ~w(per_period per_occurrence)}
  @roles ~w(owner admin head_coach coach front_desk accountant janitor)
  @max_amount 10_000_000
  @max_threshold 168
  @max_quantity 1_000
  @max_minutes 10_080

  def kinds, do: @kinds
  def units, do: @units |> Map.values() |> List.flatten()
  def roles, do: @roles

  @doc """
  Checks and normalizes a new item or a change (`current` is the stored
  item, or `%{}`). `{:ok, attrs}` or `{:error, {:invalid_fields, errors}}`.
  """
  def change(current, params) when is_map(params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)
    merged = Map.merge(stringify(current), params)
    kind = merged["kind"]
    name = if is_binary(merged["name"]), do: String.trim(merged["name"])
    roles = merged["roles"]

    errors =
      %{}
      |> check(kind in @kinds, "kind", "invalid")
      |> check(is_binary(name) and name != "" and String.length(name) <= 120, "name", "required")
      |> check(positive?(merged["amount_cents"], @max_amount), "amount_cents", "invalid")
      |> check(merged["unit"] in Map.get(@units, kind, []), "unit", "invalid")
      |> check(
        is_list(roles) and roles != [] and Enum.all?(roles, &(&1 in @roles)),
        "roles",
        "invalid"
      )
      |> check(threshold_ok?(kind, merged["weekly_threshold"]), "weekly_threshold", "invalid")
      |> check(currency?(merged["currency"]), "currency", "invalid")

    if errors == %{} do
      {:ok,
       %{
         kind: kind,
         name: name,
         amount_cents: merged["amount_cents"],
         unit: merged["unit"],
         roles: Enum.filter(@roles, &(&1 in roles)),
         weekly_threshold: merged["weekly_threshold"],
         currency: String.upcase(merged["currency"])
       }}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  def change(_current, _params), do: {:error, {:invalid_fields, %{"item" => "invalid"}}}

  defp threshold_ok?(_kind, nil), do: true

  defp threshold_ok?("overtime", value),
    do: is_integer(value) and value >= 0 and value <= @max_threshold

  defp threshold_ok?(_kind, _value), do: false

  @doc "Whether the item is counted from the classes (overtime with a threshold)."
  def computed?(%{kind: "overtime", weekly_threshold: threshold, archived_at: nil})
      when is_integer(threshold),
      do: true

  def computed?(_item), do: false

  @doc """
  The role names a person holds for pay items, from their membership
  roles and coach scope (`head_coach` for a coach who sees every client).
  """
  def person_roles(roles, coach_scope) do
    roles = roles |> List.wrap() |> Enum.map(&to_string/1)
    head? = "coach" in roles and to_string(coach_scope) == "all"
    Enum.filter(@roles, &(&1 in roles or (&1 == "head_coach" and head?)))
  end

  @doc "Whether an item applies to a person holding `roles` (`person_roles/2`)."
  def applies_to?(item, roles), do: Enum.any?(item.roles, &(&1 in roles))

  @doc """
  A pay item added to a period by hand for one person: an allowance, or
  overtime that has no threshold. `quantity` counts occurrences or extra
  classes (default 1; `per_period` is always 1), `minutes` the extra time
  of `per_hour` overtime. `note` is optional (at most 500 characters).
  """
  def manual_line(item, params, %Date{} = occurred_on, actor_id) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)
    note = blank_to_nil(params["note"])

    with :ok <- usable(item),
         {:ok, quantity, divisor} <- quantity(item.unit, params),
         :ok <- note_ok(note) do
      {:ok,
       %{
         rule_id: nil,
         pay_item_id: item.id,
         kind: item.kind,
         source_type: "manual",
         source_id: nil,
         occurred_on: occurred_on,
         description: String.slice(item.name, 0, 250),
         note: note,
         quantity: quantity,
         quantity_divisor: divisor,
         unit_cents: item.amount_cents,
         base_cents: nil,
         percent_bps: nil,
         amount_cents: Proration.amount(item.amount_cents, quantity, divisor),
         created_by_id: actor_id
       }}
    end
  end

  defp usable(%{archived_at: archived}) when not is_nil(archived),
    do: {:error, :coach_pay_item_archived}

  defp usable(item) do
    if computed?(item),
      do: {:error, {:invalid_fields, %{"pay_item_id" => "counted_from_classes"}}},
      else: :ok
  end

  defp quantity("per_period", params) do
    if params["quantity"] in [nil, 1],
      do: {:ok, 1, 1},
      else: {:error, {:invalid_fields, %{"quantity" => "invalid"}}}
  end

  defp quantity("per_hour", params) do
    minutes = params["minutes"]

    if is_integer(minutes) and minutes > 0 and minutes <= @max_minutes,
      do: {:ok, minutes, 60},
      else: {:error, {:invalid_fields, %{"minutes" => "required"}}}
  end

  defp quantity(_unit, params) do
    quantity = params["quantity"] || 1

    if positive?(quantity, @max_quantity),
      do: {:ok, quantity, 1},
      else: {:error, {:invalid_fields, %{"quantity" => "invalid"}}}
  end

  defp note_ok(nil), do: :ok

  defp note_ok(note) when is_binary(note) and byte_size(note) > 0,
    do: if(String.length(note) <= 500, do: :ok, else: invalid_note())

  defp note_ok(_note), do: invalid_note()

  defp invalid_note, do: {:error, {:invalid_fields, %{"note" => "invalid"}}}

  @doc "What an item pays by, as a statement keeps it (see `RulePolicy.terms/1`)."
  def terms(item) do
    %{
      "source" => "pay_item",
      "kind" => item.kind,
      "name" => item.name,
      "amount_cents" => item.amount_cents,
      "unit" => item.unit,
      "weekly_threshold" => item.weekly_threshold,
      "currency" => item.currency
    }
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp check(errors, true, _field, _code), do: errors
  defp check(errors, _false, field, code), do: Map.put_new(errors, field, code)

  defp positive?(value, max), do: is_integer(value) and value > 0 and value <= max

  defp currency?(value) when is_binary(value), do: String.match?(value, ~r/^[A-Za-z]{3}$/)
  defp currency?(_value), do: false

  defp stringify(%{} = map),
    do:
      map
      |> Map.drop([:__struct__, :__meta__])
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
end
