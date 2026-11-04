defmodule Palee.Infrastructure.CoachPay.EctoCoachPayStore do
  @moduledoc "Ecto adapter of the coach pay store (ADR-341), under the tenant's RLS scope."

  @behaviour Palee.CoachPay.Ports.CoachPayStore

  import Ecto.Query

  alias Palee.CoachPay.{ItemSkip, Line, PayItem, Period, Rule, Statement}
  alias Palee.CoachPay.Domain.AmountBasis
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @impl true
  def transaction(fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── Rules ───────────────────────────────────────────────────────────────

  @impl true
  def list_rules(filters) do
    Rule
    |> tenant_scope()
    |> maybe(:coach_user_id, filters[:coach_user_id] || filters["coach_user_id"])
    |> then(fn query ->
      if (filters[:include_archived] || filters["include_archived"]) in [true, "true"],
        do: query,
        else: where(query, [rule], is_nil(rule.archived_at))
    end)
    |> order_by([rule], asc: rule.coach_user_id, asc: rule.starts_on, asc: rule.inserted_at)
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  @impl true
  def get_rule(id), do: with_uuid(id, &(Rule |> tenant_scope() |> Repo.get(&1) |> plain()))

  @impl true
  def insert_rule(attrs) do
    %Rule{}
    |> Rule.changeset(attrs)
    |> Repo.insert()
    |> plain_result()
  end

  @impl true
  def update_rule(id, attrs) do
    case Rule |> tenant_scope() |> Repo.get(id) do
      nil -> {:error, :not_found}
      rule -> rule |> Rule.changeset(attrs) |> Repo.update() |> plain_result()
    end
  end

  @impl true
  def rules_between(%Date{} = from, %Date{} = to) do
    Rule
    |> tenant_scope()
    |> where([rule], rule.starts_on <= ^to and (is_nil(rule.ends_on) or rule.ends_on >= ^from))
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  # ── Periods ─────────────────────────────────────────────────────────────

  @impl true
  def list_periods(filters) do
    Period
    |> tenant_scope()
    |> maybe(:status, filters[:status] || filters["status"])
    |> order_by([period], desc: period.starts_on)
    |> limit(200)
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  @impl true
  def get_period(id), do: with_uuid(id, &(Period |> tenant_scope() |> Repo.get(&1) |> plain()))

  @impl true
  def lock_period(id) do
    with_uuid(id, fn id ->
      Period
      |> tenant_scope()
      |> where([period], period.id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> plain()
    end)
  end

  @impl true
  def insert_period(attrs) do
    %Period{}
    |> Period.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:error, %Ecto.Changeset{errors: errors}} = error ->
        if Keyword.has_key?(errors, :organization_id),
          do: {:error, :coach_pay_period_overlaps},
          else: error

      result ->
        plain_result(result)
    end
  end

  @impl true
  def update_period(id, attrs) do
    case Period |> tenant_scope() |> Repo.get(id) do
      nil -> {:error, :not_found}
      period -> period |> Period.changeset(attrs) |> Repo.update() |> plain_result()
    end
  end

  # ── Statements ──────────────────────────────────────────────────────────

  @impl true
  def statements(period_id) do
    statements =
      Statement
      |> tenant_scope()
      |> where([statement], statement.period_id == ^period_id)
      |> order_by([statement], desc: statement.total_cents, asc: statement.coach_user_id)
      |> Repo.all()

    with_lines(statements)
  end

  @impl true
  def statements_for_coach(coach_user_id, statuses) do
    Statement
    |> tenant_scope()
    |> join(:inner, [statement], period in Period, on: period.id == statement.period_id)
    |> where(
      [statement, period],
      statement.coach_user_id == ^coach_user_id and period.status in ^statuses
    )
    |> order_by([_statement, period], desc: period.starts_on)
    |> limit(36)
    |> select([statement, period], {statement, period})
    |> Repo.all()
    |> then(fn rows ->
      lines = rows |> Enum.map(&elem(&1, 0)) |> with_lines() |> Map.new(&{&1.id, &1})

      Enum.map(rows, fn {statement, period} ->
        lines
        |> Map.fetch!(statement.id)
        |> Map.put(
          :period,
          Map.take(plain(period), [:id, :starts_on, :ends_on, :status, :currency])
        )
      end)
    end)
  end

  @impl true
  def statement_totals([]), do: []

  def statement_totals(period_ids) do
    Statement
    |> tenant_scope()
    |> where([statement], statement.period_id in ^period_ids)
    |> order_by([statement], desc: statement.total_cents, asc: statement.coach_user_id)
    |> select([statement], %{
      period_id: statement.period_id,
      coach_user_id: statement.coach_user_id,
      total_cents: statement.total_cents,
      gross_cents: statement.gross_cents,
      net_cents: statement.net_cents,
      line_count: statement.line_count
    })
    |> Repo.all()
  end

  defp with_lines(statements) do
    ids = Enum.map(statements, & &1.id)

    lines =
      Line
      |> tenant_scope()
      |> where([line], line.statement_id in ^ids)
      |> order_by([line], asc: line.occurred_on, asc: line.kind, asc: line.inserted_at)
      |> Repo.all()
      |> Enum.map(&plain/1)
      |> Enum.group_by(& &1.statement_id)

    Enum.map(statements, &(&1 |> plain() |> Map.put(:lines, Map.get(lines, &1.id, []))))
  end

  @impl true
  def replace_lines(period_id, lines_by_coach, terms_by_coach, %DateTime{} = now) do
    statements = statement_map(period_id)

    # Calculated lines go; lines staff added by hand stay. The basis staff
    # chose on a calculated line is kept for its replacement (ADR-382).
    calculated =
      Line
      |> tenant_scope()
      |> where(
        [line],
        line.statement_id in ^Map.values(statements) and line.source_type != "manual"
      )

    previous =
      calculated
      |> join(:inner, [line], statement in Statement, on: statement.id == line.statement_id)
      |> select([line, statement], %{
        coach_user_id: statement.coach_user_id,
        rule_id: line.rule_id,
        pay_item_id: line.pay_item_id,
        kind: line.kind,
        source_type: line.source_type,
        source_id: line.source_id,
        occurred_on: line.occurred_on,
        amount_basis: line.amount_basis
      })
      |> Repo.all()
      |> Enum.group_by(& &1.coach_user_id)

    Repo.delete_all(calculated)

    Enum.each(lines_by_coach, fn {coach_user_id, lines} ->
      statement_id =
        Map.get(statements, coach_user_id) || insert_statement!(period_id, coach_user_id)

      lines = AmountBasis.keep_choices(lines, Map.get(previous, coach_user_id, []))
      insert_lines!(statement_id, lines, now)
      merge_terms!(statement_id, Map.get(terms_by_coach, coach_user_id, %{}))
    end)

    refresh_totals(period_id)
    update_period(period_id, Map.put(period_totals(period_id), :calculated_at, now))
  end

  @impl true
  def add_line(period_id, coach_user_id, attrs, terms) do
    statement_id =
      Map.get(statement_map(period_id), coach_user_id) ||
        insert_statement!(period_id, coach_user_id)

    %Line{}
    |> Line.changeset(Map.put(attrs, :statement_id, statement_id))
    |> Repo.insert()
    |> case do
      {:ok, line} ->
        merge_terms!(statement_id, terms)
        refresh_totals(period_id)
        update_period(period_id, period_totals(period_id))
        {:ok, plain(line)}

      error ->
        error
    end
  end

  @impl true
  def update_line_basis(period_id, line_id, basis) do
    with_uuid(line_id, fn id ->
      Line
      |> tenant_scope()
      |> where(
        [line],
        line.id == ^id and line.statement_id in ^Map.values(statement_map(period_id))
      )
      |> Repo.one()
      |> case do
        nil ->
          {:error, :not_found}

        line ->
          line |> Line.changeset(%{amount_basis: basis}) |> Repo.update!()
          refresh_totals(period_id)
          update_period(period_id, period_totals(period_id))
          :ok
      end
    end) || {:error, :not_found}
  end

  @impl true
  def delete_adjustment(period_id, line_id) do
    with_uuid(line_id, fn id ->
      {count, _} =
        Line
        |> tenant_scope()
        |> where(
          [line],
          line.id == ^id and line.source_type == "manual" and
            line.statement_id in ^Map.values(statement_map(period_id))
        )
        |> Repo.delete_all()

      if count == 1 do
        refresh_totals(period_id)
        update_period(period_id, period_totals(period_id))
        :ok
      else
        {:error, :not_found}
      end
    end) || {:error, :not_found}
  end

  # ── Recurring allowances taken off a person (ADR-510) ───────────────────

  @impl true
  def item_skips(period_id) do
    ItemSkip
    |> tenant_scope()
    |> where([skip], skip.period_id == ^period_id)
    |> order_by([skip], asc: skip.inserted_at)
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  @impl true
  def skip_pay_item_line(period_id, line_id, actor_id) do
    with_uuid(line_id, fn id ->
      statements = statement_map(period_id)
      coach_by_statement = Map.new(statements, fn {coach, statement} -> {statement, coach} end)

      line =
        Line
        |> tenant_scope()
        |> where(
          [line],
          line.id == ^id and line.source_type == "pay_item" and line.kind == "allowance" and
            line.statement_id in ^Map.values(statements)
        )
        |> Repo.one()

      case line do
        nil ->
          {:error, :not_found}

        line ->
          %ItemSkip{}
          |> ItemSkip.changeset(%{
            period_id: period_id,
            pay_item_id: line.pay_item_id,
            user_id: Map.fetch!(coach_by_statement, line.statement_id),
            created_by_id: actor_id
          })
          |> Repo.insert!(on_conflict: :nothing)

          Line
          |> tenant_scope()
          |> where(
            [other],
            other.statement_id == ^line.statement_id and other.source_type == "pay_item" and
              other.pay_item_id == ^line.pay_item_id
          )
          |> Repo.delete_all()

          refresh_totals(period_id)
          update_period(period_id, period_totals(period_id))
          :ok
      end
    end) || {:error, :not_found}
  end

  @impl true
  def delete_skip(period_id, skip_id) do
    with_uuid(skip_id, fn id ->
      {count, _} =
        ItemSkip
        |> tenant_scope()
        |> where([skip], skip.id == ^id and skip.period_id == ^period_id)
        |> Repo.delete_all()

      if count == 1, do: :ok, else: {:error, :not_found}
    end) || {:error, :not_found}
  end

  # ── Pay items (ADR-382) ──────────────────────────────────────────────────

  @impl true
  def list_items(filters) do
    PayItem
    |> tenant_scope()
    |> maybe(:kind, filters[:kind] || filters["kind"])
    |> then(fn query ->
      if (filters[:include_archived] || filters["include_archived"]) in [true, "true"],
        do: query,
        else: where(query, [item], is_nil(item.archived_at))
    end)
    |> order_by([item], asc: item.kind, asc: item.name, asc: item.inserted_at)
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  @impl true
  def get_item(id), do: with_uuid(id, &(PayItem |> tenant_scope() |> Repo.get(&1) |> plain()))

  @impl true
  def insert_item(attrs) do
    %PayItem{}
    |> PayItem.changeset(attrs)
    |> Repo.insert()
    |> plain_result()
  end

  @impl true
  def update_item(id, attrs) do
    case PayItem |> tenant_scope() |> Repo.get(id) do
      nil -> {:error, :not_found}
      item -> item |> PayItem.changeset(attrs) |> Repo.update() |> plain_result()
    end
  end

  defp statement_map(period_id) do
    Statement
    |> tenant_scope()
    |> where([statement], statement.period_id == ^period_id)
    |> select([statement], {statement.coach_user_id, statement.id})
    |> Repo.all()
    |> Map.new()
  end

  defp insert_statement!(period_id, coach_user_id) do
    %Statement{}
    |> Statement.changeset(%{period_id: period_id, coach_user_id: coach_user_id})
    |> Repo.insert!()
    |> Map.fetch!(:id)
  end

  defp merge_terms!(_statement_id, terms) when terms == %{}, do: :ok

  defp merge_terms!(statement_id, terms) do
    statement = Statement |> tenant_scope() |> Repo.get!(statement_id)

    statement
    |> Statement.changeset(%{rule_terms: Map.merge(statement.rule_terms || %{}, terms)})
    |> Repo.update!()

    :ok
  end

  defp insert_lines!(_statement_id, [], _now), do: :ok

  defp insert_lines!(statement_id, lines, now) do
    organization_id = RepoContext.current_setting("app.organization_id")

    rows =
      Enum.map(lines, fn line ->
        line
        |> Map.take([
          :rule_id,
          :kind,
          :source_type,
          :source_id,
          :occurred_on,
          :description,
          :quantity,
          :unit_cents,
          :base_cents,
          :percent_bps,
          :amount_cents,
          :pay_item_id,
          :quantity_divisor,
          :note,
          :amount_basis
        ])
        |> Map.merge(%{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          statement_id: statement_id,
          inserted_at: now,
          updated_at: now
        })
      end)

    rows
    |> Enum.chunk_every(500)
    |> Enum.each(&Repo.insert_all(Line, &1))
  end

  # Statement totals and line counts from their lines; empty statements go.
  defp refresh_totals(period_id) do
    totals =
      Line
      |> tenant_scope()
      |> join(:inner, [line], statement in Statement, on: statement.id == line.statement_id)
      |> where([_line, statement], statement.period_id == ^period_id)
      |> group_by([line], line.statement_id)
      |> select([line], {
        line.statement_id,
        sum(line.amount_cents),
        count(line.id),
        filter(sum(line.amount_cents), line.amount_basis == "net")
      })
      |> Repo.all()
      |> Map.new(fn {id, total, count, net} ->
        {id, {to_integer(total), count, to_integer(net)}}
      end)

    Statement
    |> tenant_scope()
    |> where([statement], statement.period_id == ^period_id)
    |> Repo.all()
    |> Enum.each(fn statement ->
      case Map.get(totals, statement.id) do
        nil ->
          Repo.delete!(statement)

        {total, count, net} ->
          statement
          |> Statement.changeset(%{
            total_cents: total,
            line_count: count,
            gross_cents: total - net,
            net_cents: net
          })
          |> Repo.update!()
      end
    end)
  end

  # Period totals: all lines, and gross and net apart (ADR-382).
  defp period_totals(period_id) do
    {total, gross, net} =
      Statement
      |> tenant_scope()
      |> where([statement], statement.period_id == ^period_id)
      |> select(
        [statement],
        {sum(statement.total_cents), sum(statement.gross_cents), sum(statement.net_cents)}
      )
      |> Repo.one()

    %{total_cents: to_integer(total), gross_cents: to_integer(gross), net_cents: to_integer(net)}
  end

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value) when is_integer(value), do: value

  defp maybe(query, _field, nil), do: query
  defp maybe(query, field, value), do: where(query, [row], field(row, ^field) == ^value)

  defp with_uuid(id, fun) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> fun.(id)
      :error -> nil
    end
  end

  defp tenant_scope(queryable) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _none ->
        from(row in queryable, where: false)
    end
  end

  defp plain_result({:ok, struct}), do: {:ok, plain(struct)}
  defp plain_result(error), do: error

  defp plain(nil), do: nil
  defp plain(struct), do: struct |> Map.from_struct() |> Map.drop([:__meta__])
end
