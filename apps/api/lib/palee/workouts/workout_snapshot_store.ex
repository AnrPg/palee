defmodule Palee.Workouts.WorkoutSnapshotStore do
  @moduledoc false
  @behaviour Palee.Workouts.Ports.WorkoutSnapshotStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :workout_snapshot_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def put_snapshot(context, workout_id, attrs),
    do: tenant_call(context, :put_snapshot, [workout_id, attrs])

  @impl true
  def get_snapshot(context, id), do: tenant_call(context, :get_snapshot, [id])

  @impl true
  def list_for_workout(context, workout_id),
    do: tenant_call(context, :list_for_workout, [workout_id])

  @impl true
  def attach(context, holder, holder_id, snapshot_id),
    do: tenant_call(context, :attach, [holder, holder_id, snapshot_id])

  @impl true
  def snapshot_id_of(context, holder, holder_id),
    do: tenant_call(context, :snapshot_id_of, [holder, holder_id])

  @impl true
  def referenced_by?(context, snapshot_id, user_id),
    do: tenant_call(context, :referenced_by?, [snapshot_id, user_id])
end
