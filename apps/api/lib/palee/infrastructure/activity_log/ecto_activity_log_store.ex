defmodule Palee.Infrastructure.ActivityLog.EctoActivityLogStore do
  @moduledoc """
  ADR-760: the «Αρχείο ενεργειών» in Postgres (RLS by tenant). Rows are
  only inserted; the table's trigger refuses any update but forgetting a
  person.
  """

  @behaviour Palee.ActivityLog.Ports.ActivityLogStore

  import Ecto.Query

  alias Palee.ActivityLog.Entry
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @default_limit 50
  @max_limit 500

  @impl true
  def insert(params) do
    params
    |> Entry.changeset()
    |> Repo.insert()
    |> case do
      {:ok, entry} -> {:ok, normalize(entry)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def insert_all_new([]), do: 0

  def insert_all_new(rows) when is_list(rows) do
    organization_id = RepoContext.current_setting("app.organization_id")

    rows
    |> Enum.map(&Entry.changeset/1)
    |> Enum.filter(& &1.valid?)
    |> Enum.map(fn changeset ->
      changeset
      |> Ecto.Changeset.apply_changes()
      |> Map.take(Entry.__schema__(:fields))
      |> Map.merge(%{id: Ecto.UUID.generate(), organization_id: organization_id})
    end)
    |> Enum.chunk_every(500)
    |> Enum.reduce(0, fn chunk, count ->
      {inserted, _rows} =
        Repo.insert_all(Entry, chunk,
          on_conflict: :nothing,
          conflict_target:
            {:unsafe_fragment, "(organization_id, source_ref) WHERE source_ref IS NOT NULL"}
        )

      count + inserted
    end)
  end

  @impl true
  def get(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Entry |> tenant_scope() |> where([e], e.id == ^id) |> Repo.one() |> normalize()
      :error -> nil
    end
  end

  @impl true
  def list(filters) when is_map(filters) do
    limit = filters |> Map.get(:limit, @default_limit) |> min(@max_limit) |> max(1)

    Entry
    |> tenant_scope()
    |> visible(filters)
    |> by_person(filters[:person_user_id])
    |> by_actor(filters[:actor_user_id])
    |> by_actions(filters[:actions])
    |> by_window(filters[:from], filters[:to])
    |> by_query(filters[:query], filters[:matching_user_ids] || [])
    |> shared_only(filters[:shared_only])
    |> sensitive_only(filters[:sensitive_only])
    |> before(filters[:before])
    |> order_by([e], desc: e.occurred_at, desc: e.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def forget_person(user_id) do
    %{rows: [[count]]} =
      Repo.query!("SELECT palee_forget_activity_person($1)", [Ecto.UUID.dump!(user_id)])

    count
  end

  @impl true
  def people_ids do
    Entry
    |> tenant_scope()
    |> select([e], [e.person_user_id, e.actor_user_id])
    |> distinct(true)
    |> Repo.all()
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @impl true
  def backfill_version do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) ->
        Repo.one(
          from(b in "activity_log_backfills",
            where: b.organization_id == type(^organization_id, :binary_id),
            select: b.version
          )
        )

      _none ->
        nil
    end
  end

  @impl true
  def mark_backfilled(version, entries) do
    organization_id = RepoContext.current_setting("app.organization_id")
    now = DateTime.utc_now()

    Repo.insert_all(
      "activity_log_backfills",
      [
        %{
          organization_id: Ecto.UUID.dump!(organization_id),
          version: version,
          entries: entries,
          done_at: now
        }
      ],
      on_conflict: [set: [version: version, entries: entries, done_at: now]],
      conflict_target: [:organization_id]
    )

    :ok
  end

  # ── Filters ─────────────────────────────────────────────────────────────

  # `areas` are read whole; `own_areas` only where the reader is the person.
  defp visible(query, %{areas: areas, own_areas: own, reader_id: reader})
       when is_list(areas) and is_list(own) and own != [] and is_binary(reader) do
    where(query, [e], e.area in ^areas or (e.area in ^own and e.person_user_id == ^reader))
  end

  defp visible(query, %{areas: areas}) when is_list(areas),
    do: where(query, [e], e.area in ^areas)

  defp visible(query, _filters), do: query

  defp by_person(query, nil), do: query
  defp by_person(query, user_id), do: where(query, [e], e.person_user_id == ^user_id)

  defp by_actor(query, nil), do: query
  defp by_actor(query, user_id), do: where(query, [e], e.actor_user_id == ^user_id)

  defp by_actions(query, actions) when is_list(actions) and actions != [],
    do: where(query, [e], e.action in ^actions)

  defp by_actions(query, _actions), do: query

  defp by_window(query, from, to) do
    query
    |> then(fn q -> if from, do: where(q, [e], e.occurred_at >= ^from), else: q end)
    |> then(fn q -> if to, do: where(q, [e], e.occurred_at < ^to), else: q end)
  end

  # Free text: the reason, the subject's name, or a person whose name matched.
  defp by_query(query, text, user_ids) when is_binary(text) and text != "" do
    pattern = "%" <> escape_like(text) <> "%"

    where(
      query,
      [e],
      ilike(e.reason, ^pattern) or ilike(e.subject_label, ^pattern) or
        e.person_user_id in ^user_ids or e.actor_user_id in ^user_ids
    )
  end

  defp by_query(query, _text, _user_ids), do: query

  defp shared_only(query, true), do: where(query, [e], e.reason_shared == true)
  defp shared_only(query, _), do: query

  defp sensitive_only(query, true), do: where(query, [e], e.sensitive == true)
  defp sensitive_only(query, _), do: query

  defp before(query, {%DateTime{} = at, id}) when is_binary(id) do
    where(query, [e], e.occurred_at < ^at or (e.occurred_at == ^at and e.id < ^id))
  end

  defp before(query, _cursor), do: query

  defp escape_like(text), do: String.replace(text, ~r/([\\%_])/, "\\\\\\1")

  defp tenant_scope(queryable) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _none ->
        from(row in queryable, where: false)
    end
  end

  defp normalize(nil), do: nil

  defp normalize(%Entry{} = entry) do
    entry
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end
end
