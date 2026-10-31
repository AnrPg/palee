defmodule Palee.CoachPay do
  @moduledoc """
  CP-A6 (ADR-341): coach pay and commissions. Rules per coach (per class,
  per attendee, per personal-training session, percent of the sales
  attributed to them), pay periods, one statement per coach and period,
  approval and an export for the accountant.

  Coach pay is a report for payroll, not payroll: it reads the schedule
  and the money through `Palee.CoachPay.Ports.WorkSource` and never writes
  Finance or issues fiscal documents.
  """

  alias Palee.CoachPay.CoachPayStore
  alias Palee.CoachPay.Domain.{PayCalculator, PeriodPolicy, RulePolicy, StatementExport}

  defp scoped(context, fun), do: CoachPayStore.with_tenant_context(context, fun)
  defp work_source, do: Application.fetch_env!(:palee, :coach_pay_work_source)

  @doc "The injected clock (`:coach_pay_clock`)."
  def clock, do: Application.fetch_env!(:palee, :coach_pay_clock)

  # ── Rules ───────────────────────────────────────────────────────────────

  @doc "Rule kinds, who counts in a class, and sales scopes (for the API's enums)."
  def rule_kinds, do: RulePolicy.kinds()
  def rule_count_statuses, do: RulePolicy.count_statuses()
  def rule_sales_scopes, do: RulePolicy.sales_scopes()

  def list_rules(context, filters \\ %{}),
    do: scoped(context, fn -> CoachPayStore.list_rules(filters) end)

  def create_rule(context, params, actor_id) do
    with {:ok, attrs} <- RulePolicy.change(%{}, params) do
      scoped(context, fn ->
        CoachPayStore.insert_rule(Map.put(attrs, :created_by_id, actor_id))
      end)
    end
  end

  @doc """
  Changes a rule. A rule that already paid in an approved period keeps its
  terms there: approved statements are snapshots, never recalculated.
  """
  def update_rule(context, id, params) do
    scoped(context, fn ->
      with %{} = rule <- CoachPayStore.get_rule(id) || {:error, :not_found},
           true <- is_nil(rule.archived_at) || {:error, :coach_pay_rule_archived},
           {:ok, attrs} <- RulePolicy.change(rule, params) do
        CoachPayStore.update_rule(id, attrs)
      end
    end)
  end

  @doc "Archives a rule: it pays nothing after `today` (gym-local)."
  def archive_rule(context, id, %Date{} = today, %DateTime{} = now) do
    scoped(context, fn ->
      with %{} = rule <- CoachPayStore.get_rule(id) || {:error, :not_found} do
        if rule.archived_at,
          do: {:ok, rule},
          else:
            CoachPayStore.update_rule(
              id,
              rule |> RulePolicy.archive(today) |> Map.put(:archived_at, now)
            )
      end
    end)
  end

  # ── Periods ─────────────────────────────────────────────────────────────

  def list_periods(context, filters \\ %{}),
    do: scoped(context, fn -> CoachPayStore.list_periods(filters) end)

  def create_period(context, %Date{} = starts_on, %Date{} = ends_on, currency, actor_id) do
    scoped(context, fn ->
      existing = CoachPayStore.list_periods(%{})

      with :ok <- PeriodPolicy.validate_new(starts_on, ends_on, existing) do
        CoachPayStore.insert_period(%{
          starts_on: starts_on,
          ends_on: ends_on,
          status: "draft",
          currency: currency,
          created_by_id: actor_id
        })
      end
    end)
  end

  @doc "The period with its statements and their lines."
  def get_period(context, id) do
    scoped(context, fn ->
      case CoachPayStore.get_period(id) do
        nil -> {:error, :not_found}
        period -> {:ok, Map.put(period, :statements, CoachPayStore.statements(period.id))}
      end
    end)
  end

  @doc """
  Calculates a draft period from the rules and the period's work and money
  (read before the lock, outside the transaction), keeping adjustments.
  """
  def calculate(context, id, %DateTime{} = now) do
    with {:ok, period} <- get_period(context, id),
         :ok <- PeriodPolicy.editable?(period) do
      work = %{
        classes: work_source().classes(context, period.starts_on, period.ends_on),
        sessions: work_source().sessions(context, period.starts_on, period.ends_on),
        sales: work_source().sales(context, period.starts_on, period.ends_on)
      }

      scoped(context, fn ->
        CoachPayStore.transaction(fn ->
          with %{} = locked <- CoachPayStore.lock_period(id) || {:error, :not_found},
               :ok <- PeriodPolicy.editable?(locked) do
            rules = CoachPayStore.rules_between(period.starts_on, period.ends_on)
            lines = PayCalculator.calculate(rules, work, period.currency)
            CoachPayStore.replace_lines(id, lines, now)
          end
        end)
      end)
      |> then(fn
        {:ok, _period} -> get_period(context, id)
        error -> error
      end)
    end
  end

  def add_adjustment(context, id, coach_user_id, params, actor_id) do
    scoped(context, fn ->
      CoachPayStore.transaction(fn ->
        with %{} = period <- CoachPayStore.lock_period(id) || {:error, :not_found},
             :ok <- PeriodPolicy.editable?(period),
             {:ok, line} <- PeriodPolicy.adjustment(params, period.ends_on, actor_id) do
          CoachPayStore.add_line(id, coach_user_id, line)
        end
      end)
    end)
    |> then(fn
      {:ok, _line} -> get_period(context, id)
      error -> error
    end)
  end

  def delete_adjustment(context, id, line_id) do
    scoped(context, fn ->
      CoachPayStore.transaction(fn ->
        with %{} = period <- CoachPayStore.lock_period(id) || {:error, :not_found},
             :ok <- PeriodPolicy.editable?(period),
             :ok <- CoachPayStore.delete_adjustment(id, line_id) do
          {:ok, :deleted}
        end
      end)
    end)
    |> then(fn
      {:ok, _deleted} -> get_period(context, id)
      error -> error
    end)
  end

  def approve(context, id, actor_id, %DateTime{} = now),
    do: transition(context, id, &PeriodPolicy.approve(&1, actor_id, now))

  def reopen(context, id, reason),
    do: transition(context, id, &PeriodPolicy.reopen(&1, reason))

  defp transition(context, id, change) do
    scoped(context, fn ->
      CoachPayStore.transaction(fn ->
        with %{} = period <- CoachPayStore.lock_period(id) || {:error, :not_found},
             {:ok, attrs} <- change.(period) do
          CoachPayStore.update_period(id, attrs)
        end
      end)
    end)
    |> then(fn
      {:ok, _period} -> get_period(context, id)
      error -> error
    end)
  end

  @doc "The approved period as CSV for the accountant; marks it exported."
  def export(context, id, names, %DateTime{} = now) do
    with {:ok, period} <- get_period(context, id),
         {:ok, attrs} <- PeriodPolicy.export(period, now),
         {:ok, _updated} <- scoped(context, fn -> CoachPayStore.update_period(id, attrs) end) do
      {:ok, StatementExport.csv(period, period.statements, names)}
    end
  end

  @doc "A coach's own approved and exported statements, newest first."
  def coach_statements(context, coach_user_id),
    do:
      scoped(context, fn ->
        CoachPayStore.statements_for_coach(coach_user_id, ["approved", "exported"])
      end)

  # ── Tenant data (ADR-117) ───────────────────────────────────────────────

  def tenant_data_policy, do: Palee.CoachPay.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
