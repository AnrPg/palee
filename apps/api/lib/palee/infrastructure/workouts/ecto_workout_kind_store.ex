defmodule Palee.Infrastructure.Workouts.EctoWorkoutKindStore do
  @moduledoc """
  Postgres store of ADR-690: a box's own workout types (tenant table, read
  and written in the open tenant session), the kinds the Palee team added
  and the team's queue (platform tables).

  A merge or a Palee decision rewrites the box's WODs and sections in the
  same transaction as the type's new status, so no WOD ever points at a type
  the box no longer offers without a way back (`merged_into`).
  """

  @behaviour Palee.Workouts.Ports.WorkoutKindStore

  import Ecto.Query

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  alias Palee.Workouts.{
    MasterWorkout,
    OrganizationWorkoutKind,
    WorkoutKindAddition,
    WorkoutKindCandidate,
    WorkoutSection
  }

  alias Palee.Workouts.Domain.WorkoutKinds

  # --- The box's catalogue (open tenant session) ---

  @impl true
  def catalogue do
    %{additions: additions(), box: list_box_kinds()}
  end

  @impl true
  def additions do
    WorkoutKindAddition
    |> order_by([a], asc: a.inserted_at)
    |> Repo.all()
    |> Enum.map(&addition_map/1)
  end

  @impl true
  def list_box_kinds do
    OrganizationWorkoutKind
    |> scoped_to_tenant()
    |> order_by([k], asc: k.folded)
    |> Repo.all()
    |> Enum.map(&kind_map/1)
  end

  @impl true
  def get_box_kind(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %OrganizationWorkoutKind{} = kind <-
           OrganizationWorkoutKind |> scoped_to_tenant() |> Repo.get(uuid) do
      kind_map(kind)
    else
      _ -> nil
    end
  end

  @impl true
  def find_box_kind_by_folded(folded) do
    OrganizationWorkoutKind
    |> scoped_to_tenant()
    |> where([k], k.folded == ^folded and k.status != "merged")
    |> Repo.one()
    |> then(&(&1 && kind_map(&1)))
  end

  @impl true
  def insert_box_kind(attrs) do
    organization_id = RepoContext.current_setting("app.organization_id")

    %OrganizationWorkoutKind{}
    |> Ecto.Changeset.change(Map.put(attrs, :organization_id, organization_id))
    |> Ecto.Changeset.unique_constraint(:folded, name: :organization_workout_kinds_folded_index)
    |> Repo.insert()
    |> case do
      {:ok, kind} -> {:ok, kind_map(kind)}
      {:error, %Ecto.Changeset{}} -> {:error, :workout_kind_exists}
    end
  end

  @impl true
  def update_box_kind(id, changes) do
    case OrganizationWorkoutKind |> scoped_to_tenant() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      kind ->
        kind
        |> Ecto.Changeset.change(changes)
        |> Ecto.Changeset.unique_constraint(:folded,
          name: :organization_workout_kinds_folded_index
        )
        |> Repo.update()
        |> case do
          {:ok, kind} -> {:ok, kind_map(kind)}
          {:error, %Ecto.Changeset{}} -> {:error, :workout_kind_exists}
        end
    end
  end

  @impl true
  def merge_box_kind(id, target_ref) do
    Repo.transaction(fn ->
      kind =
        OrganizationWorkoutKind
        |> scoped_to_tenant()
        |> where([k], k.id == ^id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      case kind do
        nil ->
          Repo.rollback(:not_found)

        kind ->
          {:ok, merged} =
            kind
            |> Ecto.Changeset.change(status: "merged", merged_into: target_ref)
            |> Repo.update()

          rewritten = rewrite_refs(WorkoutKinds.box_ref(kind.id), target_ref)
          %{kind: kind_map(merged), workouts: rewritten}
      end
    end)
  end

  @impl true
  def refresh_box_kind(id) do
    ref = WorkoutKinds.box_ref(id)
    rewrite_refs(ref, ref)
  end

  # Every WOD and section of the box with `from` gets `to` instead, and the
  # WOD's families and compatibility type follow.
  defp rewrite_refs(from, to) do
    catalogue = catalogue()

    workouts =
      MasterWorkout
      |> scoped_to_tenant()
      |> where([w], ^from in w.types)
      |> select([w], %{id: w.id, types: w.types})
      |> Repo.all()

    Enum.each(workouts, fn %{id: id, types: types} ->
      types = WorkoutKinds.rewrite(types, from, to, catalogue)

      MasterWorkout
      |> where([w], w.id == ^id)
      |> Repo.update_all(
        set: [
          types: types,
          families: WorkoutKinds.families(types, catalogue),
          type: legacy_type(types)
        ]
      )
    end)

    WorkoutSection
    |> scoped_to_tenant()
    |> where([s], ^from in s.types)
    |> select([s], %{id: s.id, types: s.types})
    |> Repo.all()
    |> Enum.each(fn %{id: id, types: types} ->
      WorkoutSection
      |> where([s], s.id == ^id)
      |> Repo.update_all(set: [types: WorkoutKinds.rewrite(types, from, to, catalogue)])
    end)

    length(workouts)
  end

  defp legacy_type(types) do
    case WorkoutKinds.legacy_type(types) do
      nil -> nil
      key -> String.to_existing_atom(key)
    end
  end

  # --- The Palee team's queue (platform tables, no tenant) ---

  @impl true
  def note_box_kind_candidate(
        %{label: label, folded: folded, family: family},
        organization_id,
        now
      ) do
    note_candidate(label, folded, now, fn candidate ->
      votes =
        if organization_id in candidate.organization_ids,
          do: candidate.family_votes,
          else: Map.update(candidate.family_votes, family, 1, &(&1 + 1))

      %{
        family_votes: votes,
        organization_ids: Enum.uniq(candidate.organization_ids ++ [organization_id])
      }
    end)
  end

  @impl true
  def note_profile_suggestion(name, folded, suggestion_id, now) do
    note_candidate(name, folded, now, fn candidate ->
      %{profile_suggestion_ids: Enum.uniq(candidate.profile_suggestion_ids ++ [suggestion_id])}
    end)
  end

  # One row per folded name; a decided name reopens when a new box or a new
  # suggestion brings it back only if it was kept for the boxes.
  defp note_candidate(label, folded, now, change) do
    Repo.transaction(fn ->
      candidate =
        WorkoutKindCandidate
        |> where([c], c.folded == ^folded)
        |> lock("FOR UPDATE")
        |> Repo.one() ||
          %WorkoutKindCandidate{
            label: label,
            folded: folded,
            family_votes: %{},
            organization_ids: [],
            profile_suggestion_ids: [],
            status: "pending",
            first_seen_at: now
          }

      candidate
      |> Ecto.Changeset.change(Map.put(change.(candidate), :last_seen_at, now))
      |> Repo.insert_or_update!()
    end)
  end

  @impl true
  def list_candidates(status, limit) do
    WorkoutKindCandidate
    |> where([c], c.status == ^status)
    |> order_by([c], asc: c.first_seen_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @impl true
  def recently_decided(limit) do
    WorkoutKindCandidate
    |> where([c], c.status != "pending")
    |> order_by([c], desc: c.decided_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @impl true
  def get_candidate(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(WorkoutKindCandidate, uuid)
      :error -> nil
    end
  end

  @impl true
  def record_decision(candidate_id, status, decision, addition, actor_user_id, now) do
    Repo.transaction(fn ->
      candidate =
        WorkoutKindCandidate
        |> where([c], c.id == ^candidate_id and c.status == "pending")
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(candidate), do: Repo.rollback(:not_found)

      if addition do
        %WorkoutKindAddition{}
        |> Ecto.Changeset.change(
          Map.merge(addition, %{candidate_id: candidate.id, added_by_id: actor_user_id})
        )
        |> Ecto.Changeset.unique_constraint(:key)
        |> Repo.insert()
        |> case do
          {:ok, _addition} -> :ok
          {:error, _changeset} -> Repo.rollback(:workout_kind_key_taken)
        end
      end

      candidate
      |> Ecto.Changeset.change(
        status: status,
        decision: decision,
        decided_at: now,
        decided_by_id: actor_user_id
      )
      |> Repo.update!()
    end)
  end

  @impl true
  def undigested_candidates do
    WorkoutKindCandidate
    |> where([c], c.status == "pending" and is_nil(c.digested_at))
    |> order_by([c], asc: c.first_seen_at)
    |> Repo.all()
  end

  @impl true
  def mark_digested(ids, now) do
    {count, _rows} =
      WorkoutKindCandidate
      |> where([c], c.id in ^ids)
      |> Repo.update_all(set: [digested_at: now])

    count
  end

  @impl true
  def box_kinds_by_ids([]), do: []

  def box_kinds_by_ids(ids) do
    %{rows: rows} =
      Repo.query!(
        "SELECT id, label, family, status, merged_into FROM palee_workout_kinds_by_ids($1::uuid[])",
        [Enum.map(ids, &Ecto.UUID.dump!/1)]
      )

    Enum.map(rows, fn [id, label, family, status, merged_into] ->
      id = Ecto.UUID.load!(id)

      %{
        id: id,
        ref: WorkoutKinds.box_ref(id),
        label: label,
        family: family,
        status: status,
        merged_into: merged_into
      }
    end)
  end

  @impl true
  def box_kinds_with_folded(folded) do
    OrganizationWorkoutKind
    |> scoped_to_tenant()
    |> where([k], k.folded == ^folded and k.status != "merged")
    |> Repo.all()
    |> Enum.map(&kind_map/1)
  end

  defp kind_map(%OrganizationWorkoutKind{} = kind) do
    %{
      id: kind.id,
      ref: WorkoutKinds.box_ref(kind.id),
      label: kind.label,
      folded: kind.folded,
      family: kind.family,
      status: kind.status,
      merged_into: kind.merged_into,
      created_by_id: kind.created_by_id,
      inserted_at: kind.inserted_at
    }
  end

  defp addition_map(%WorkoutKindAddition{} = addition) do
    %{key: addition.key, family: addition.family, labels: addition.labels || %{}}
  end

  defp scoped_to_tenant(query) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) ->
        where(query, [row], row.organization_id == ^organization_id)

      _no_tenant_context ->
        where(query, [row], false)
    end
  end
end
