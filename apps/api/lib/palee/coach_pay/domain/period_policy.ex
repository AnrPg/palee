defmodule Palee.CoachPay.Domain.PeriodPolicy do
  @moduledoc """
  CP-A6 (ADR-341): a pay period's life, pure.

      draft ─► approved ─► exported
        ▲          │
        └─ reopen ─┘   (with a reason; an exported period stays as it is)

  A draft is calculated (again and again) and adjusted; an approved
  period is locked: what the coaches and the accountant see does not
  change under them. Periods are at most 92 days and never overlap.
  """

  @max_days 92

  def max_days, do: @max_days

  @doc "Checks a new period's dates against the box's other periods."
  def validate_new(%Date{} = starts_on, %Date{} = ends_on, existing) do
    cond do
      Date.compare(ends_on, starts_on) == :lt ->
        {:error, {:invalid_fields, %{"ends_on" => "invalid"}}}

      Date.diff(ends_on, starts_on) > @max_days ->
        {:error, {:invalid_fields, %{"ends_on" => "too_long"}}}

      Enum.any?(existing, &overlaps?(&1, starts_on, ends_on)) ->
        {:error, :coach_pay_period_overlaps}

      true ->
        :ok
    end
  end

  def validate_new(_starts_on, _ends_on, _existing),
    do: {:error, {:invalid_fields, %{"starts_on" => "required"}}}

  defp overlaps?(period, starts_on, ends_on),
    do:
      Date.compare(period.starts_on, ends_on) != :gt and
        Date.compare(period.ends_on, starts_on) != :lt

  @doc "Whether lines may change (calculate, adjust)."
  def editable?(%{status: "draft"}), do: :ok
  def editable?(_period), do: {:error, :coach_pay_period_locked}

  def approve(%{status: "draft"}, actor_id, now),
    do:
      {:ok, %{status: "approved", approved_at: now, approved_by_id: actor_id, reopen_reason: nil}}

  def approve(_period, _actor_id, _now), do: {:error, :coach_pay_period_locked}

  def reopen(%{status: "approved"}, reason) when is_binary(reason) do
    reason = String.trim(reason)

    if reason == "" or String.length(reason) > 200,
      do: {:error, {:invalid_fields, %{"reason" => "required"}}},
      else:
        {:ok, %{status: "draft", approved_at: nil, approved_by_id: nil, reopen_reason: reason}}
  end

  def reopen(%{status: "approved"}, _reason),
    do: {:error, {:invalid_fields, %{"reason" => "required"}}}

  def reopen(%{status: "exported"}, _reason), do: {:error, :coach_pay_period_exported}
  def reopen(_period, _reason), do: {:error, :coach_pay_period_not_approved}

  @doc "Exporting needs an approved period; exporting again is fine."
  def export(%{status: status}, now) when status in ["approved", "exported"],
    do: {:ok, %{status: "exported", exported_at: now}}

  def export(_period, _now), do: {:error, :coach_pay_period_not_approved}

  @doc "A staff adjustment line (a bonus, a correction): any non-zero amount with a reason."
  def adjustment(params, %Date{} = occurred_on, actor_id) do
    amount = params["amount_cents"] || params[:amount_cents]
    description = params["description"] || params[:description]

    cond do
      not (is_integer(amount) and amount != 0 and abs(amount) <= 10_000_000) ->
        {:error, {:invalid_fields, %{"amount_cents" => "invalid"}}}

      not (is_binary(description) and String.trim(description) != "" and
               String.length(description) <= 250) ->
        {:error, {:invalid_fields, %{"description" => "required"}}}

      true ->
        {:ok,
         %{
           rule_id: nil,
           kind: "adjustment",
           source_type: "manual",
           source_id: nil,
           occurred_on: occurred_on,
           description: String.trim(description),
           quantity: 1,
           unit_cents: nil,
           base_cents: nil,
           percent_bps: nil,
           amount_cents: amount,
           created_by_id: actor_id
         }}
    end
  end
end
