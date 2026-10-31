defmodule Palee.Infrastructure.Leads.EctoLeadStore do
  @moduledoc "ADR-344: leads, their tasks and history in Postgres (forced RLS per box)."

  @behaviour Palee.Leads.Ports.LeadStore

  import Ecto.Query

  alias Palee.Leads.{Lead, LeadEvent, LeadTask}
  alias Palee.Leads.Domain.Pipeline
  alias Palee.Repo

  @default_limit 50
  @max_limit 200

  @impl true
  def transaction(_context, fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:error, reason} -> Repo.rollback(reason)
        {:ok, result} -> result
        result -> result
      end
    end)
  end

  @impl true
  def insert(_context, attrs), do: attrs |> Lead.create_changeset() |> Repo.insert()

  @impl true
  def update(_context, %Lead{} = lead, changes),
    do: lead |> Lead.update_changeset(changes) |> Repo.update()

  @impl true
  def get(context, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      context |> scoped(Lead) |> where([l], l.id == ^id) |> Repo.one()
    else
      _error -> nil
    end
  end

  @impl true
  def get_for_update(context, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      context |> scoped(Lead) |> where([l], l.id == ^id) |> lock("FOR UPDATE") |> Repo.one()
    else
      _error -> nil
    end
  end

  @impl true
  def get_by_source_ref(context, source, ref) do
    context
    |> scoped(Lead)
    |> where([l], l.source == ^source and l.source_ref == ^ref)
    |> Repo.one()
  end

  @impl true
  def find_by_email(context, email) do
    open = Pipeline.open_stages()

    context
    |> scoped(Lead)
    |> where([l], l.email == ^email and l.stage != "converted")
    |> order_by([l], desc: l.stage in ^open, desc: l.stage_changed_at)
    |> limit(1)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  @impl true
  def open_for_person(context, user_id, email) do
    open = Pipeline.open_stages()
    query = context |> scoped(Lead) |> where([l], l.stage in ^open)

    case email do
      email when is_binary(email) and email != "" ->
        email = String.downcase(email)
        where(query, [l], l.user_id == ^user_id or l.email == ^email)

      _none ->
        where(query, [l], l.user_id == ^user_id)
    end
    |> order_by([l], asc: l.inserted_at)
    |> Repo.all()
  end

  @impl true
  def list(context, filters) do
    limit = filters |> Map.get(:limit, @default_limit) |> min(@max_limit) |> max(1)

    context
    |> scoped(Lead)
    |> filter_stages(Map.get(filters, :stages))
    |> filter_eq(:owner_id, Map.get(filters, :owner_id))
    |> filter_eq(:source, Map.get(filters, :source))
    |> filter_q(Map.get(filters, :q))
    |> order_by([l], desc: l.inserted_at, desc: l.id)
    |> limit(^limit)
    |> offset(^max(Map.get(filters, :offset, 0), 0))
    |> Repo.all()
  end

  defp filter_stages(query, stages) when is_list(stages) and stages != [],
    do: where(query, [l], l.stage in ^stages)

  defp filter_stages(query, _stages), do: query

  defp filter_eq(query, _field, nil), do: query
  defp filter_eq(query, field, value), do: where(query, [l], field(l, ^field) == ^value)

  defp filter_q(query, q) when is_binary(q) and q != "" do
    pattern = "%" <> String.replace(q, ~w(\\ % _), &("\\" <> &1)) <> "%"

    where(
      query,
      [l],
      ilike(l.name, ^pattern) or ilike(l.email, ^pattern) or ilike(l.phone, ^pattern)
    )
  end

  defp filter_q(query, _q), do: query

  @impl true
  def stage_counts(context) do
    context
    |> scoped(Lead)
    |> group_by([l], l.stage)
    |> select([l], {l.stage, count(l.id)})
    |> Repo.all()
    |> Map.new()
  end

  @impl true
  def delete(context, id) do
    case get(context, id) do
      nil ->
        {:error, :not_found}

      lead ->
        {:ok, _deleted} = Repo.delete(lead)
        :ok
    end
  end

  @impl true
  def add_event(_context, attrs), do: attrs |> LeadEvent.changeset() |> Repo.insert()

  @impl true
  def events(context, lead_id) do
    context
    |> scoped(LeadEvent)
    |> where([e], e.lead_id == ^lead_id)
    |> order_by([e], desc: e.at, desc: e.inserted_at)
    |> Repo.all()
  end

  @impl true
  def insert_task(_context, attrs), do: attrs |> LeadTask.create_changeset() |> Repo.insert()

  @impl true
  def get_task(context, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      context |> scoped(LeadTask) |> where([t], t.id == ^id) |> Repo.one()
    else
      _error -> nil
    end
  end

  @impl true
  def complete_task(_context, %LeadTask{} = task, changes),
    do: task |> LeadTask.done_changeset(changes) |> Repo.update()

  @impl true
  def tasks(context, lead_id) do
    context
    |> scoped(LeadTask)
    |> where([t], t.lead_id == ^lead_id)
    |> order_by([t], asc: not is_nil(t.done_at), asc: t.due_at, desc: t.done_at)
    |> Repo.all()
  end

  @impl true
  def open_tasks(context, filters) do
    open = Pipeline.open_stages()
    limit = filters |> Map.get(:limit, @default_limit) |> min(@max_limit) |> max(1)

    context
    |> scoped(LeadTask)
    |> join(:inner, [t], l in Lead, on: l.id == t.lead_id and l.stage in ^open)
    |> where([t], is_nil(t.done_at))
    |> then(fn query ->
      case Map.get(filters, :assignee_id) do
        nil -> query
        id -> where(query, [t], t.assignee_id == ^id)
      end
    end)
    |> then(fn query ->
      case Map.get(filters, :due_before) do
        nil -> query
        at -> where(query, [t], t.due_at < ^at)
      end
    end)
    |> order_by([t], asc: t.due_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @impl true
  def next_tasks(_context, []), do: %{}

  def next_tasks(context, lead_ids) do
    context
    |> scoped(LeadTask)
    |> where([t], t.lead_id in ^lead_ids and is_nil(t.done_at))
    |> distinct([t], t.lead_id)
    |> order_by([t], asc: t.lead_id, asc: t.due_at)
    |> Repo.all()
    |> Map.new(&{&1.lead_id, &1})
  end

  @impl true
  def purge_stale(context, %DateTime{} = cutoff) do
    {count, _rows} =
      context
      |> scoped(Lead)
      |> where([l], l.stage == "lost" and is_nil(l.user_id) and l.stage_changed_at < ^cutoff)
      |> Repo.delete_all()

    count
  end

  # Forced RLS already hides other boxes; the explicit filter keeps a query
  # run outside a box scope from ever reading anything.
  defp scoped(%{organization_id: organization_id}, queryable) when is_binary(organization_id),
    do: from(row in queryable, where: row.organization_id == ^organization_id)

  defp scoped(_context, queryable), do: from(row in queryable, where: false)
end
