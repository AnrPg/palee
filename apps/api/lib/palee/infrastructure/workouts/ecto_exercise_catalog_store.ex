defmodule Palee.Infrastructure.Workouts.EctoExerciseCatalogStore do
  @moduledoc "Postgres store of the exercise catalog's additions, candidates and audit trail (ADR-461)."

  @behaviour Palee.Workouts.Ports.ExerciseCatalogStore

  import Ecto.Query

  alias Palee.Repo
  alias Palee.Workouts.{ExerciseCatalogAddition, ExerciseCatalogAuditEvent, ExerciseNameCandidate}

  @impl true
  def additions do
    from(a in ExerciseCatalogAddition,
      order_by: [asc: a.inserted_at],
      select: %{kind: a.kind, catalog_slug: a.catalog_slug, label: a.label, category: a.category}
    )
    |> Repo.all()
  end

  @impl true
  def note_candidates([], _now), do: :ok

  def note_candidates(entries, now) do
    rows =
      Enum.map(entries, fn entry ->
        %{
          id: Ecto.UUID.generate(),
          name: entry.name,
          folded: entry.folded,
          uses_count: 1,
          owners_count: if(entry.new_owner?, do: 1, else: 0),
          status: "pending",
          first_seen_at: now,
          last_seen_at: now,
          inserted_at: now,
          updated_at: now
        }
      end)

    {_count, _rows} =
      Repo.insert_all(ExerciseNameCandidate, rows,
        on_conflict:
          from(c in ExerciseNameCandidate,
            update: [
              set: [
                uses_count: fragment("? + 1", c.uses_count),
                owners_count: fragment("? + EXCLUDED.owners_count", c.owners_count),
                last_seen_at: fragment("EXCLUDED.last_seen_at"),
                updated_at: fragment("EXCLUDED.updated_at")
              ]
            ]
          ),
        conflict_target: [:folded]
      )

    :ok
  end

  @impl true
  def list_candidates(status, min_owners, limit) do
    from(c in ExerciseNameCandidate,
      where: c.status == ^status and c.owners_count >= ^min_owners,
      order_by: [desc: c.owners_count, desc: c.uses_count, desc: c.last_seen_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @impl true
  def get_candidate(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(ExerciseNameCandidate, uuid)
      :error -> nil
    end
  end

  @impl true
  def record_decision(candidate_id, decision, actor_user_id, metadata, now) do
    Repo.transaction(fn ->
      candidate =
        Repo.one(
          from(c in ExerciseNameCandidate,
            where: c.id == ^candidate_id and c.status == "pending",
            lock: "FOR UPDATE"
          )
        ) || Repo.rollback(:exercise_candidate_already_decided)

      addition = insert_addition(decision.addition, candidate, actor_user_id, now)

      status = if decision.action == "reject", do: "rejected", else: "approved"

      {1, [updated]} =
        Repo.update_all(
          from(c in ExerciseNameCandidate, where: c.id == ^candidate.id, select: c),
          set: [
            status: status,
            catalog_slug: decision.catalog_slug,
            decided_at: now,
            decided_by_id: actor_user_id,
            updated_at: now
          ]
        )

      Repo.insert!(%ExerciseCatalogAuditEvent{
        action: decision.action,
        actor_user_id: actor_user_id,
        candidate_id: candidate.id,
        catalog_slug: decision.catalog_slug,
        metadata: Map.merge(metadata, %{"candidate_name" => candidate.name}),
        inserted_at: now
      })

      %{candidate: updated, addition: addition}
    end)
  end

  defp insert_addition(nil, _candidate, _actor, _now), do: nil

  defp insert_addition(attrs, candidate, actor_user_id, now) do
    case Repo.insert(
           struct(
             ExerciseCatalogAddition,
             Map.merge(attrs, %{
               candidate_id: candidate.id,
               approved_by_id: actor_user_id,
               inserted_at: now
             })
           )
           |> Ecto.Changeset.change()
           |> Ecto.Changeset.unique_constraint(:catalog_slug,
             name: :exercise_catalog_additions_entry_slug_index
           )
           |> Ecto.Changeset.unique_constraint(:folded,
             name: :exercise_catalog_additions_folded_index
           )
         ) do
      {:ok, addition} -> addition
      {:error, _changeset} -> Repo.rollback(:exercise_already_in_catalog)
    end
  end

  @impl true
  def audit_events(limit) do
    from(e in ExerciseCatalogAuditEvent, order_by: [desc: e.inserted_at], limit: ^limit)
    |> Repo.all()
  end
end
