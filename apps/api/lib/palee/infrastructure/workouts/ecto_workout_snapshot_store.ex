defmodule Palee.Infrastructure.Workouts.EctoWorkoutSnapshotStore do
  @moduledoc "Postgres storage of WOD snapshots (ADR-357)."

  @behaviour Palee.Workouts.Ports.WorkoutSnapshotStore

  import Ecto.Query

  alias Palee.Execution.{TrainingLogEntry, WorkoutExecution}
  alias Palee.Repo
  alias Palee.Workouts.{AssignedWorkout, AssignedWorkoutAthlete, WorkoutSnapshotRecord}

  @impl true
  def put_snapshot(%{organization_id: organization_id} = context, workout_id, attrs) do
    params =
      Map.merge(attrs, %{organization_id: organization_id, master_workout_id: workout_id})

    %WorkoutSnapshotRecord{}
    |> WorkoutSnapshotRecord.changeset(params)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:organization_id, :master_workout_id, :content_hash]
    )
    |> case do
      {:ok, %WorkoutSnapshotRecord{id: nil}} -> existing(context, workout_id, attrs.content_hash)
      {:ok, record} -> {:ok, normalize(record)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp existing(%{organization_id: organization_id}, workout_id, hash) do
    WorkoutSnapshotRecord
    |> where([s], s.organization_id == ^organization_id)
    |> where([s], s.master_workout_id == ^workout_id and s.content_hash == ^hash)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      record -> {:ok, normalize(record)}
    end
  end

  @impl true
  def get_snapshot(%{organization_id: organization_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        WorkoutSnapshotRecord
        |> Repo.get_by(id: id, organization_id: organization_id)
        |> normalize()

      :error ->
        nil
    end
  end

  @impl true
  def list_for_workout(%{organization_id: organization_id}, workout_id) do
    WorkoutSnapshotRecord
    |> where([s], s.organization_id == ^organization_id and s.master_workout_id == ^workout_id)
    |> order_by([s], asc: s.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def attach(context, holder, holder_id, snapshot_id) do
    {count, _rows} =
      holder
      |> holder_query(context, holder_id)
      |> Repo.update_all(set: [workout_snapshot_id: snapshot_id])

    if count == 1, do: :ok, else: {:error, :not_found}
  end

  @impl true
  def snapshot_id_of(context, holder, holder_id) do
    holder
    |> holder_query(context, holder_id)
    |> select([row], row.workout_snapshot_id)
    |> Repo.one()
  end

  @impl true
  def referenced_by?(%{organization_id: org}, snapshot_id, user_id) do
    execution? =
      from(e in WorkoutExecution,
        where:
          e.organization_id == ^org and e.workout_snapshot_id == ^snapshot_id and
            e.user_id == ^user_id
      )
      |> Repo.exists?()

    log? =
      from(t in TrainingLogEntry,
        where:
          t.organization_id == ^org and t.workout_snapshot_id == ^snapshot_id and
            t.user_id == ^user_id
      )
      |> Repo.exists?()

    assignment? =
      from(a in AssignedWorkout,
        join: athlete in AssignedWorkoutAthlete,
        on: athlete.assigned_workout_id == a.id,
        where:
          a.organization_id == ^org and a.workout_snapshot_id == ^snapshot_id and
            athlete.athlete_id == ^user_id
      )
      |> Repo.exists?()

    execution? or log? or assignment?
  end

  defp holder_query(:assignment, %{organization_id: org}, id),
    do: from(a in AssignedWorkout, where: a.id == ^id and a.organization_id == ^org)

  defp holder_query(:execution, %{organization_id: org}, id),
    do: from(e in WorkoutExecution, where: e.id == ^id and e.organization_id == ^org)

  defp holder_query(:training_log, %{organization_id: org}, id),
    do: from(t in TrainingLogEntry, where: t.id == ^id and t.organization_id == ^org)

  defp normalize(nil), do: nil

  defp normalize(%WorkoutSnapshotRecord{} = record) do
    Map.take(record, [
      :id,
      :master_workout_id,
      :content_hash,
      :format_version,
      :title,
      :content,
      :inserted_at
    ])
  end
end
