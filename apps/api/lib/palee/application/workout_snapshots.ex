defmodule Palee.Application.WorkoutSnapshots do
  @moduledoc """
  ADR-357 (CP-D3): freezing a WOD when it is assigned or performed.

    * `capture_for/4` – after an assignment is created, a run is completed
      or a score is logged: snapshots the WOD (one row per distinct
      content) and points the holder at it. A failure is logged and never
      fails the assignment or the result: the snapshot is a record of what
      happened, not a condition for it.
    * `get/2` – one snapshot, for staff who program or follow training, or
      for the person whose own assignment, run or score points at it.

  Editing the template later, or reopening and editing the class's copy,
  changes neither the snapshot nor what the holder points at.
  """

  require Logger

  alias Palee.{Organizations, Workouts}
  alias Palee.Workouts.WorkoutSnapshotStore

  @holders [:assignment, :execution, :training_log]

  @doc "Snapshots `workout_id` and attaches it to the holder. Always `:ok`."
  def capture_for(_context, _holder, _holder_id, nil), do: :ok

  def capture_for(%{organization_id: org} = context, holder, holder_id, workout_id)
      when holder in @holders and is_binary(org) and is_binary(holder_id) do
    with {:ok, snapshot} <- capture(context, workout_id),
         :ok <- WorkoutSnapshotStore.attach(context, holder, holder_id, snapshot.id) do
      :ok
    else
      error ->
        Logger.warning(
          "workout snapshot not taken for #{holder} #{holder_id}: #{inspect(error, limit: 5)}"
        )

        :ok
    end
  end

  def capture_for(_context, _holder, _holder_id, _workout_id), do: :ok

  @doc "Stores the WOD's current content (or finds the identical snapshot)."
  def capture(context, workout_id) do
    case Workouts.get_workout_for_admin(context, workout_id) do
      %{} = workout ->
        WorkoutSnapshotStore.put_snapshot(context, workout_id, Workouts.build_snapshot(workout))

      _missing ->
        {:error, :not_found}
    end
  end

  @doc "A snapshot, if the viewer may read it."
  def get(%{organization_id: org} = context, id) when is_binary(org) do
    case WorkoutSnapshotStore.get_snapshot(context, id) do
      nil ->
        {:error, :workout_snapshot_not_found}

      snapshot ->
        if staff_reader?(context) or own?(context, snapshot.id),
          do: {:ok, present(snapshot)},
          else: {:error, :workout_snapshot_not_found}
    end
  end

  def get(_context, _id), do: {:error, :organization_context_required}

  @doc "The snapshot a holder points at, if any (`nil` before ADR-357)."
  def of(context, holder, holder_id) when holder in @holders do
    case WorkoutSnapshotStore.snapshot_id_of(context, holder, holder_id) do
      nil -> nil
      id -> context |> WorkoutSnapshotStore.get_snapshot(id) |> present()
    end
  end

  def present(nil), do: nil

  def present(snapshot) do
    %{
      id: snapshot.id,
      workout_id: snapshot.master_workout_id,
      title: snapshot.title,
      content_hash: snapshot.content_hash,
      format_version: snapshot.format_version,
      taken_at: snapshot.inserted_at,
      content: snapshot.content
    }
  end

  defp staff_reader?(context),
    do:
      Organizations.can?(context, :manage_workouts) or
        Organizations.can?(context, :view_client_training)

  defp own?(context, snapshot_id),
    do: WorkoutSnapshotStore.referenced_by?(context, snapshot_id, context.user_id)
end
