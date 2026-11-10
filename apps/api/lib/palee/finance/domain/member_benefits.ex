defmodule Palee.Finance.Domain.MemberBenefits do
  @moduledoc """
  ADR-612: what the box gives a member for free («Δώρο ή χάρη»). Pure rules;
  the store keeps the ledger (`finance_member_benefits`) and the application
  service carries each grant out.

  Five kinds (ANR 2026-11-10):

    * `grace`: the member keeps access until `ends_on`; what they owe stays
      owed and the reminders wait until the grace is over;
    * `free_access`: access without a package until `ends_on`;
    * `extra_uses`: more of an allowance (class visits, coaching
      touchpoints…), for a period the staff choose every time;
    * `package`: a package given free for its current period, or at a price
      the staff set (0 is free for good);
    * `debt_forgiven`: open charges settled by a non-cash credit.

  Grace and free access always end on a day (ANR: never open-ended) and are
  what opens access (`access/2`). Grace, free access and extra uses can be
  revoked; a package or a forgiven debt is undone with the tools that undo
  those (ending the package, a new charge).
  """

  @kinds ~w(grace free_access extra_uses package debt_forgiven)
  @access_kinds ~w(grace free_access)
  @revocable ~w(grace free_access extra_uses)
  @allowances ~w(class_visits coaching_touchpoints event_visits guest_passes open_gym_visits)
  @periods ~w(calendar_week calendar_month subscription_period)
  @max_quantity 10_000
  @max_reason 500

  @sources %{"grace" => "staff_grace", "free_access" => "staff_free_access"}

  def kinds, do: @kinds
  def access_kinds, do: @access_kinds
  def revocable_kinds, do: @revocable
  def periods, do: @periods

  @doc "The entitlement sources an access benefit gives (`InvoiceLifecycle`)."
  def entitlement_sources, do: Map.values(@sources)

  @doc "The entitlement source of an access benefit's kind."
  def entitlement_source(kind) when is_map_key(@sources, kind), do: Map.fetch!(@sources, kind)

  @doc "The access kind behind an entitlement source, or nil."
  def kind_of_source(source) do
    Enum.find_value(@sources, fn {kind, value} -> if value == source, do: kind end)
  end

  @doc "Whether `kind` can be revoked."
  def revocable?(kind), do: kind in @revocable

  @doc """
  Checks and shapes what the staff asked for. `today` is the box's date.
  Answers `{:ok, grant}` with string keys only for what the kind uses, plus
  `"reason"` (nil when blank), or `{:error, reason}`.
  """
  def validate_grant(params, %Date{} = today) when is_map(params) do
    with {:ok, kind} <- kind(params["kind"]),
         {:ok, reason} <- reason(params["reason"]),
         {:ok, grant} <- validate_kind(kind, params, today) do
      {:ok, grant |> Map.put("kind", kind) |> Map.put("reason", reason)}
    end
  end

  def validate_grant(_params, _today), do: {:error, :invalid_benefit}

  defp kind(kind) when kind in @kinds, do: {:ok, kind}
  defp kind(_kind), do: {:error, :invalid_benefit_kind}

  @doc "A reason given by staff: trimmed, nil when blank, at most 500 characters."
  def reason(nil), do: {:ok, nil}

  def reason(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        {:ok, nil}

      trimmed ->
        if String.length(trimmed) <= @max_reason,
          do: {:ok, trimmed},
          else: {:error, :benefit_reason_too_long}
    end
  end

  def reason(_value), do: {:error, :invalid_benefit}

  defp validate_kind(kind, params, today) when kind in @access_kinds do
    case date(params["ends_on"]) do
      %Date{} = ends_on ->
        if Date.compare(ends_on, today) == :lt,
          do: {:error, :benefit_ends_in_past},
          else: {:ok, %{"starts_on" => today, "ends_on" => ends_on}}

      nil ->
        {:error, :benefit_end_required}
    end
  end

  defp validate_kind("extra_uses", params, _today) do
    allowance = params["allowance"]
    quantity = params["quantity"]
    period = params["period"]

    cond do
      not allowance?(allowance) ->
        {:error, :invalid_benefit_allowance}

      not (is_integer(quantity) and quantity in 1..@max_quantity) ->
        {:error, :invalid_benefit_quantity}

      period not in @periods ->
        {:error, :benefit_period_required}

      true ->
        {:ok, %{"allowance" => allowance, "quantity" => quantity, "period" => period}}
    end
  end

  defp validate_kind("package", params, _today) do
    with {:ok, package_id} <- uuid(params["package_id"], :invalid_benefit_package),
         {:ok, pricing} <- pricing(params["pricing"]) do
      {:ok, Map.merge(%{"package_id" => package_id}, pricing)}
    end
  end

  defp validate_kind("debt_forgiven", params, _today) do
    case params["invoice_ids"] do
      [_ | _] = ids ->
        ids
        |> Enum.reduce_while({:ok, []}, fn id, {:ok, acc} ->
          case uuid(id, :invalid_benefit_invoice) do
            {:ok, id} -> {:cont, {:ok, [id | acc]}}
            error -> {:halt, error}
          end
        end)
        |> case do
          {:ok, ids} -> {:ok, %{"invoice_ids" => ids |> Enum.reverse() |> Enum.uniq()}}
          error -> error
        end

      _none ->
        {:error, :benefit_invoices_required}
    end
  end

  # The staff choose every time (no default, ANR's rule on invented values):
  # free for the period running now, or a price for every period.
  defp pricing(%{"mode" => "this_period_free"}), do: {:ok, %{"pricing" => "this_period_free"}}

  defp pricing(%{"mode" => "price", "price_cents" => cents})
       when is_integer(cents) and cents >= 0,
       do: {:ok, %{"pricing" => "price", "price_cents" => cents}}

  defp pricing(_other), do: {:error, :benefit_pricing_required}

  defp allowance?(value) when value in @allowances, do: true

  defp allowance?("class_visits:" <> id), do: match?({:ok, _}, Ecto.UUID.cast(id))
  defp allowance?(_value), do: false

  defp uuid(value, error) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, error}
    end
  end

  defp date(%Date{} = date), do: date

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _error -> nil
    end
  end

  defp date(_value), do: nil

  @doc """
  The access a member has from benefits on `today`: `%{kind, until}` of the
  grant that lasts longest, or nil. `grants` are access grants; `revoked` the
  ids of those revoked.
  """
  def access(grants, revoked, %Date{} = today) do
    revoked = MapSet.new(revoked)

    grants
    |> Enum.filter(&(&1.kind in @access_kinds and not MapSet.member?(revoked, &1.id)))
    |> Enum.filter(&covers?(&1, today))
    |> Enum.max_by(& &1.ends_on, Date, fn -> nil end)
    |> case do
      nil -> nil
      grant -> %{kind: grant.kind, until: grant.ends_on}
    end
  end

  defp covers?(%{starts_on: %Date{} = starts, ends_on: %Date{} = ends}, today),
    do: Date.compare(starts, today) != :gt and Date.compare(ends, today) != :lt

  defp covers?(_grant, _today), do: false

  @doc """
  Where a grant stands on `today`, for the history: `revoked`, `upcoming`,
  `active`, `ended` (an access or extra uses past their last day) or `given`
  (a package or a forgiven debt, done once).
  """
  def state(grant, revoked?, %Date{} = today) do
    last_day = grant.ends_on

    cond do
      revoked? ->
        "revoked"

      grant.kind in ["package", "debt_forgiven"] ->
        "given"

      match?(%Date{}, grant.starts_on) and Date.compare(grant.starts_on, today) == :gt ->
        "upcoming"

      match?(%Date{}, last_day) and Date.compare(last_day, today) == :lt ->
        "ended"

      true ->
        "active"
    end
  end
end
