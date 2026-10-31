defmodule Palee.Infrastructure.CoachPay.EctoCoachPayStore do
  @moduledoc "Ecto adapter of the coach pay store (ADR-341), under the tenant's RLS scope."

  @behaviour Palee.CoachPay.Ports.CoachPayStore

  import Ecto.Query

  alias Palee.CoachPay.{Line, Period, Rule, Statement}
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
        |> Map.put(:period, Map.take(plain(period), [:id, :starts_on, :ends_on, :status, :currency]))
      end)
    end)
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
  def replace_lines(period_id, lines_by_coach, %DateTime{} = now) do
    statements = statement_map(period_id)

    # Calculated lines go; staff adjustments stay.
    Line
    |> tenant_scope()
    |> where([line], line.statement_id in ^Map.values(statements) and line.kind != "adjustment")
    |> Repo.delete_all()

    Enum.each(lines_by_coach, fn {coach_user_id, lines} ->
      statement_id = Map.get(statements, coach_user_id) || insert_statement!(period_id, coach_user_id)
      insert_lines!(statement_id, lines, now)
    end)

    refresh_totals(period_id)
    update_period(period_id, %{calculated_at: now, total_cents: period_total(period_id)})
  end

  @impl true
  def add_line(period_id, coach_user_id, attrs) do
    statement_id =
      Map.get(statement_map(period_id), coach_user_id) || insert_statement!(period_id, coach_user_id)

    %Line{}
    |> Line.changeset(Map.put(attrs, :statement_id, statement_id))
    |> Repo.insert()
    |> case do
      {:ok, line} ->
        refresh_totals(period_id)
        update_period(period_id, %{total_cents: period_total(period_id)})
        {:ok, plain(line)}

      error ->
        error
    end
  end

  @impl true
  def delete_adjustment(period_id, line_id) do
    with_uuid(line_id, fn id ->
      {count, _} =
        Line
        |> tenant_scope()
        |> where(
          [line],
          line.id == ^id and line.kind == "adjustment" and
            line.statement_id in ^Map.values(statement_map(period_id))
        )
        |> Repo.delete_all()

      if count == 1 do
        refresh_totals(period_id)
        update_period(period_id, %{total_cents: period_total(period_id)})
        :ok
      else
        {:error, :not_found}
      end
    end) || {:error, :not_found}
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
          :amount_cents
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
      |> select([line], {line.statement_id, sum(line.amount_cents), count(line.id)})
      |> Repo.all()
      |> Map.new(fn {id, total, count} -> {id, {to_integer(total), count}} end)

    Statement
    |> tenant_scope()
    |> where([statement], statement.period_id == ^period_id)
    |> Repo.all()
    |> Enum.each(fn statement ->
      case Map.get(totals, statement.id) do
        nil ->
          Repo.delete!(statement)

        {total, count} ->
          statement
          |> Statement.changeset(%{total_cents: total, line_count: count})
          |> Repo.update!()
      end
    end)
  end

  defp period_total(period_id) do
    Statement
    |> tenant_scope()
    |> where([statement], statement.period_id == ^period_id)
    |> select([statement], sum(statement.total_cents))
    |> Repo.one()
    |> to_integer()
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
