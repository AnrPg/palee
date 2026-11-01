defmodule Palee.CoachPay do
  @moduledoc """
  CP-A6 (ADR-341): coach pay and commissions. Rules per coach (per class,
  per attendee, per personal-training session, percent of the sales
  attributed to them), pay periods, one statement per coach and period,
  approval and an export for the accountant.

  ADR-382 adds fixed pay (monthly, weekly, daily, prorated), a percent of
  the subscriptions of the coach's own clients or of the whole box, the
  box's catalogue of overtime and allowances, payments by hand with their
  reason, groups per rule on each statement, the internal pay statement as
  PDF («Εκκαθαριστικό») and summaries for Finance and the staff profile.

  Coach pay is a report for payroll, not payroll: it reads the schedule
  and the money through `Palee.CoachPay.Ports.WorkSource` and never writes
  Finance or issues fiscal documents.
  """

  alias Palee.CoachPay.CoachPayStore

  alias Palee.CoachPay.Domain.{
    AmountBasis,
    PayCalculator,
    PayItemPolicy,
    PeriodPolicy,
    RulePolicy,
    StatementExport,
    StatementGroups
  }

  defp scoped(context, fun), do: CoachPayStore.with_tenant_context(context, fun)
  defp work_source, do: Application.fetch_env!(:palee, :coach_pay_work_source)

  @doc "The injected clock (`:coach_pay_clock`)."
  def clock, do: Application.fetch_env!(:palee, :coach_pay_clock)

  # ── Rules ───────────────────────────────────────────────────────────────

  @doc "Rule kinds, who counts in a class, and sales scopes (for the API's enums)."
  def rule_kinds, do: RulePolicy.kinds()
  def rule_count_statuses, do: RulePolicy.count_statuses()
  def rule_sales_scopes, do: RulePolicy.sales_scopes()
  def rule_frequencies, do: RulePolicy.frequencies()
  def amount_bases, do: AmountBasis.bases()

  @doc "Pay item kinds, units and roles (ADR-382, for the API's enums)."
  def pay_item_kinds, do: PayItemPolicy.kinds()
  def pay_item_units, do: PayItemPolicy.units()
  def pay_item_roles, do: PayItemPolicy.roles()

  @doc "A person's pay-item roles from their membership roles and coach scope."
  def person_roles(roles, coach_scope), do: PayItemPolicy.person_roles(roles, coach_scope)

  @doc "Kinds of every statement line (for the API's enums)."
  def line_kinds,
    do:
      RulePolicy.kinds() ++
        ["clawback"] ++ PeriodPolicy.manual_kinds() ++ PayItemPolicy.kinds()

  @doc "Where a line comes from (for the API's enums)."
  def line_sources,
    do: ~w(scheduled_class appointment_slot finance_payment finance_reversal manual rule pay_item)

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
        nil ->
          {:error, :not_found}

        period ->
          statements = period.id |> CoachPayStore.statements() |> Enum.map(&with_groups/1)
          {:ok, Map.put(period, :statements, statements)}
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
        period: Map.take(period, [:starts_on, :ends_on]),
        classes: work_source().classes(context, period.starts_on, period.ends_on),
        sessions: work_source().sessions(context, period.starts_on, period.ends_on),
        sales: work_source().sales(context, period.starts_on, period.ends_on),
        coach_clients: work_source().coach_clients(context, period.starts_on, period.ends_on),
        staff_roles: work_source().staff_roles(context)
      }

      scoped(context, fn ->
        CoachPayStore.transaction(fn ->
          with %{} = locked <- CoachPayStore.lock_period(id) || {:error, :not_found},
               :ok <- PeriodPolicy.editable?(locked) do
            rules = CoachPayStore.rules_between(period.starts_on, period.ends_on)
            items = CoachPayStore.list_items(%{kind: "overtime"})
            work = Map.put(work, :pay_items, items)
            lines = PayCalculator.calculate(rules, work, period.currency)
            terms = PayCalculator.terms_by_coach(rules, items, lines)
            CoachPayStore.replace_lines(id, lines, terms, now)
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
          CoachPayStore.add_line(id, coach_user_id, line, %{})
        end
      end)
    end)
    |> then(fn
      {:ok, _line} -> get_period(context, id)
      error -> error
    end)
  end

  @doc """
  ADR-382: an allowance (or overtime that has no weekly threshold) from the
  box's catalogue, added by hand to one person's statement in a draft
  period. `person_roles` are the person's pay-item roles
  (`PayItemPolicy.person_roles/2`); the item must apply to one of them.
  """
  def add_pay_item_line(context, id, user_id, person_roles, params, actor_id) do
    item_id = params["pay_item_id"] || params[:pay_item_id]

    scoped(context, fn ->
      CoachPayStore.transaction(fn ->
        with %{} = period <- CoachPayStore.lock_period(id) || {:error, :not_found},
             :ok <- PeriodPolicy.editable?(period),
             %{} = item <- CoachPayStore.get_item(item_id) || {:error, :not_found},
             :ok <- currency(item, period),
             :ok <- applies(item, person_roles),
             {:ok, line} <- PayItemPolicy.manual_line(item, params, period.ends_on, actor_id) do
          CoachPayStore.add_line(id, user_id, line, %{item.id => PayItemPolicy.terms(item)})
        end
      end)
    end)
    |> then(fn
      {:ok, _line} -> get_period(context, id)
      error -> error
    end)
  end

  defp currency(%{currency: currency}, %{currency: currency}), do: :ok

  defp currency(_item, _period),
    do: {:error, {:invalid_fields, %{"pay_item_id" => "other_currency"}}}

  defp applies(item, roles) do
    if PayItemPolicy.applies_to?(item, roles),
      do: :ok,
      else: {:error, {:invalid_fields, %{"user_id" => "role_not_covered"}}}
  end

  @doc """
  ADR-382: whether a line of a draft period is gross or net. A calculated
  line takes its rule's basis again when the period is calculated again;
  a line added by hand keeps it.
  """
  def set_line_basis(context, id, line_id, basis) do
    scoped(context, fn ->
      CoachPayStore.transaction(fn ->
        with %{} = period <- CoachPayStore.lock_period(id) || {:error, :not_found},
             :ok <- PeriodPolicy.editable?(period),
             {:ok, %{amount_basis: basis}} <- PeriodPolicy.basis_change(basis),
             :ok <- CoachPayStore.update_line_basis(id, line_id, basis) do
          {:ok, :updated}
        end
      end)
    end)
    |> then(fn
      {:ok, _updated} -> get_period(context, id)
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
    do: coach_statements(context, coach_user_id, ["approved", "exported"])

  @doc "A coach's statements in periods of these statuses, newest first, with their groups."
  def coach_statements(context, coach_user_id, statuses) do
    context
    |> scoped(fn -> CoachPayStore.statements_for_coach(coach_user_id, statuses) end)
    |> Enum.map(&with_groups/1)
  end

  @doc """
  ADR-382: one coach's statement of an approved or exported period, with
  its period and groups (for the pay statement PDF).
  """
  def approved_statement(context, period_id, coach_user_id) do
    with {:ok, period} <- get_period(context, period_id),
         :ok <- approved(period),
         %{} = statement <-
           Enum.find(period.statements, &(&1.coach_user_id == coach_user_id)) ||
             {:error, :not_found} do
      {:ok, %{period: Map.delete(period, :statements), statement: statement}}
    end
  end

  defp approved(%{status: status}) when status in ["approved", "exported"], do: :ok
  defp approved(_period), do: {:error, :coach_pay_period_not_approved}

  @doc """
  ADR-382: Finance's summary: periods (newest first, those starting
  between `from` and `to` when given) with each coach's total.
  """
  def summary(context, filters) do
    scoped(context, fn ->
      periods =
        %{}
        |> CoachPayStore.list_periods()
        |> Enum.filter(&in_range?(&1, filters[:from], filters[:to]))

      totals =
        periods
        |> Enum.map(& &1.id)
        |> CoachPayStore.statement_totals()
        |> Enum.group_by(& &1.period_id)

      Enum.map(periods, &Map.put(&1, :statements, Map.get(totals, &1.id, [])))
    end)
  end

  defp in_range?(period, from, to),
    do:
      (is_nil(from) or Date.compare(period.starts_on, from) != :lt) and
        (is_nil(to) or Date.compare(period.starts_on, to) != :gt)

  @doc """
  A statement with its groups per rule (ADR-382), each line marked when its
  amount is `net` (`deviates_from_default`) and the count of such lines.
  """
  def with_groups(%{lines: lines} = statement) do
    lines = Enum.map(lines, &Map.put(&1, :deviates_from_default, AmountBasis.deviates?(&1)))

    statement
    |> Map.put(:lines, lines)
    |> Map.put(:groups, StatementGroups.groups(statement))
    |> Map.put(:net_line_count, Enum.count(lines, & &1.deviates_from_default))
  end

  def with_groups(statement), do: statement

  # ── Pay items (ADR-382) ─────────────────────────────────────────────────

  def list_items(context, filters \\ %{}),
    do: scoped(context, fn -> CoachPayStore.list_items(filters) end)

  def create_item(context, params, actor_id) do
    with {:ok, attrs} <- PayItemPolicy.change(%{}, params) do
      scoped(context, fn ->
        CoachPayStore.insert_item(Map.put(attrs, :created_by_id, actor_id))
      end)
    end
  end

  @doc "Changes an item; statements already calculated keep the terms they paid by."
  def update_item(context, id, params) do
    scoped(context, fn ->
      with %{} = item <- CoachPayStore.get_item(id) || {:error, :not_found},
           true <- is_nil(item.archived_at) || {:error, :coach_pay_item_archived},
           {:ok, attrs} <- PayItemPolicy.change(item, params) do
        CoachPayStore.update_item(id, attrs)
      end
    end)
  end

  @doc "Archives an item: it is no longer counted or added (lines already made stay)."
  def archive_item(context, id, %DateTime{} = now) do
    scoped(context, fn ->
      with %{} = item <- CoachPayStore.get_item(id) || {:error, :not_found} do
        if item.archived_at,
          do: {:ok, item},
          else: CoachPayStore.update_item(id, %{archived_at: now})
      end
    end)
  end

  # ── Tenant data (ADR-117) ───────────────────────────────────────────────

  def tenant_data_policy, do: Palee.CoachPay.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
