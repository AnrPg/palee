defmodule Palee.Application.LoggedWorkoutChangeNotice do
  @moduledoc """
  ADR-393: after a coach or staff member saves a WOD that people already
  performed, the people whose run or score now reads differently from the WOD
  hear it once (bell and push, notification `logged_workout_changed`, category
  `coach`, so their notification choices apply), with a link to that entry in
  their Journal, where «Το WOD άλλαξε από τότε» opens the WOD as it was.
  Nobody else hears it, and never the editor.

  The save itself is the burst: `PublishWorkout` calls `notify/2` once per
  publish, whatever it changed. A failure is logged and never fails the save.
  """

  require Logger

  alias Palee.{Notifications, Workouts}
  alias Palee.Workouts.Domain.LoggedWorkoutChange
  alias Palee.Workouts.WorkoutSnapshotStore

  @doc "Notifies the people concerned; answers the ids of the people notified."
  def notify(%{organization_id: org} = context, workout_id) when is_binary(org) do
    case Workouts.get_workout_for_admin(context, workout_id) do
      %{} = workout ->
        current_hash = Workouts.build_snapshot(workout).content_hash

        context
        |> WorkoutSnapshotStore.list_performed(workout_id)
        |> LoggedWorkoutChange.recipients(current_hash, Map.get(context, :user_id))
        |> Enum.flat_map(&tell(&1, org, workout, current_hash))

      _missing ->
        []
    end
  rescue
    error ->
      Logger.warning("logged workout change notice failed: #{Exception.message(error)}")
      []
  end

  def notify(_context, _workout_id), do: []

  defp tell(result, org, workout, current_hash) do
    case Notifications.process_event("logged_workout_changed", %{
           user_id: result.user_id,
           organization_id: org,
           workout_id: workout.id,
           workout_title: Map.get(workout, :title),
           holder: Atom.to_string(result.holder),
           holder_id: result.holder_id,
           dedupe_key: LoggedWorkoutChange.dedupe_key(workout.id, current_hash),
           url: LoggedWorkoutChange.journal_url(result.holder_id)
         }) do
      {:error, reason} ->
        Logger.warning("logged_workout_changed not delivered: #{inspect(reason)}")
        []

      _delivered_or_muted ->
        [result.user_id]
    end
  end
end
