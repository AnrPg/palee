defmodule Palee.Infrastructure.Workouts.EctoExerciseCatalogStore do
  @moduledoc """
  Postgres store of the exercise catalog's additions, candidates and audit
  trail (ADR-461), and the writer of the reference catalog tables the Palee
  team's decisions change (ADR-560): an approved entry becomes an exercise
  (with the targets given), an approved alias a Quick Text alias, and a
  target edit replaces an exercise's targets, each with its audit event in
  the same transaction. Readers notice through the revision the tables'
  trigger bumps.
  """

  @behaviour Palee.Workouts.Ports.ExerciseCatalogStore

  import Ecto.Query

  alias Palee.Repo
  alias Palee.Workouts.{ExerciseCatalogAddition, ExerciseCatalogAuditEvent, ExerciseNameCandidate}

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
      insert_reference(decision.addition, Map.get(decision, :targets), now)

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
  def replace_exercise_targets(exercise_id, targets, actor_user_id, now) do
    Repo.transaction(fn ->
      %{num_rows: found} =
        Repo.query!("SELECT 1 FROM exercises WHERE id = $1 FOR UPDATE", [exercise_id])

      if found == 0, do: Repo.rollback(:not_found)

      before = current_targets(exercise_id)
      Repo.query!("DELETE FROM exercise_muscle_targets WHERE exercise_id = $1", [exercise_id])
      Repo.query!("DELETE FROM exercise_quality_targets WHERE exercise_id = $1", [exercise_id])
      insert_targets(exercise_id, targets)
      Repo.query!("UPDATE exercises SET updated_at = $2 WHERE id = $1", [exercise_id, now])

      Repo.insert!(%ExerciseCatalogAuditEvent{
        action: "set_targets",
        actor_user_id: actor_user_id,
        catalog_slug: exercise_id,
        metadata: %{"before" => before, "after" => plain_targets(targets)},
        inserted_at: now
      })

      %{exercise_id: exercise_id, targets: targets}
    end)
  end

  # ADR-560: the reference rows of an approved decision.
  defp insert_reference(nil, _targets, _now), do: :ok

  defp insert_reference(%{kind: "entry"} = addition, targets, now) do
    case Repo.query(
           """
           INSERT INTO exercises (id, label, normalized, category, origin, inserted_at, updated_at)
           VALUES ($1, $2, $3, $4, 'reviewed', $5, $5)
           """,
           [
             addition.catalog_slug,
             addition.label,
             normalized(addition.label),
             addition.category,
             now
           ]
         ) do
      {:ok, _result} ->
        insert_targets(addition.catalog_slug, targets || %{muscles: [], qualities: []})

      {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} ->
        Repo.rollback(:exercise_already_in_catalog)
    end
  end

  defp insert_reference(%{kind: "alias"} = addition, _targets, now) do
    case Repo.query(
           """
           INSERT INTO exercise_aliases (id, exercise_id, alias, normalized, kind, position, inserted_at)
           SELECT $1, e.id, $3, $4, 'resolve',
             coalesce((SELECT max(a.position) + 1 FROM exercise_aliases a
                       WHERE a.exercise_id = e.id AND a.kind = 'resolve'), 0), $5
           FROM exercises e WHERE e.id = $2
           """,
           [
             Ecto.UUID.bingenerate(),
             addition.catalog_slug,
             addition.label,
             normalized(addition.label),
             now
           ]
         ) do
      {:ok, %{num_rows: 1}} ->
        :ok

      {:ok, %{num_rows: 0}} ->
        Repo.rollback(:unknown_exercise_catalog_slug)

      {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} ->
        Repo.rollback(:exercise_already_in_catalog)
    end
  end

  defp insert_targets(exercise_id, %{muscles: muscles, qualities: qualities}) do
    Enum.each(muscles, fn %{id: muscle_id, role: role} ->
      %{num_rows: 1} =
        Repo.query!(
          """
          INSERT INTO exercise_muscle_targets (exercise_id, muscle_id, muscle_kind, role)
          SELECT $1, m.id, m.kind, $3 FROM muscles m
          WHERE m.id = $2 AND m.kind IN ('group', 'head')
          """,
          [exercise_id, muscle_id, to_string(role)]
        )
    end)

    Enum.each(qualities, fn quality_id ->
      Repo.query!(
        "INSERT INTO exercise_quality_targets (exercise_id, quality_id) VALUES ($1, $2)",
        [exercise_id, quality_id]
      )
    end)
  end

  defp current_targets(exercise_id) do
    %{rows: muscles} =
      Repo.query!(
        "SELECT muscle_id, role FROM exercise_muscle_targets WHERE exercise_id = $1 ORDER BY muscle_id",
        [exercise_id]
      )

    %{rows: qualities} =
      Repo.query!(
        "SELECT quality_id FROM exercise_quality_targets WHERE exercise_id = $1 ORDER BY quality_id",
        [exercise_id]
      )

    %{
      "muscles" => Enum.map(muscles, fn [id, role] -> %{"id" => id, "role" => role} end),
      "qualities" => List.flatten(qualities)
    }
  end

  defp plain_targets(%{muscles: muscles, qualities: qualities}) do
    %{
      "muscles" => Enum.map(muscles, &%{"id" => &1.id, "role" => to_string(&1.role)}),
      "qualities" => qualities
    }
  end

  defp normalized(label), do: Palee.Catalog.Domain.Reference.normalize_name(label)

  @impl true
  def audit_events(limit) do
    from(e in ExerciseCatalogAuditEvent, order_by: [desc: e.inserted_at], limit: ^limit)
    |> Repo.all()
  end
end
