defmodule Palee.Application.ClassWorkouts.SetClassWorkouts do
  @moduledoc """
  ADR-746: sets every WOD of a class, in order («+ WOD», reorder, remove).

  The first WOD stays the class's `master_workout_id`. A WOD new to the
  class is filed in the day's Classes folder like the first one
  (`ClassWorkoutFiling`), so the class keeps its own copy; WODs it already
  has stay as they are. A class that inherited the day's WOD becomes its own
  list once the list changes. «Τώρα» and the people who chose a removed WOD
  go back to the first WOD and to «Θα αποφασίσω στο box».
  """

  alias Palee.Application.{FileWorkoutCopy, ScheduleRealtime, WorkoutLibraryFolders}
  alias Palee.{Organizations, Scheduling}
  alias Palee.Scheduling.Domain.ClassWorkouts

  def call(%{organization_id: _} = context, slot_id, workout_ids) do
    with :ok <- ClassWorkouts.validate_list(workout_ids),
         %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found},
         :ok <- Organizations.authorize_location(context, Map.get(slot, :location_id)),
         {:ok, filed} <- file_new(context, slot, workout_ids),
         :ok <- ClassWorkouts.validate_list(Enum.map(filed, & &1.id)) do
      case Scheduling.set_class_workouts(context, slot.id, Enum.map(filed, & &1.id)) do
        {:ok, updated} ->
          announce(updated)
          {:ok, updated}

        error ->
          Enum.each(filed, &discard(context, &1))
          error
      end
    end
  end

  def call(_context, _slot_id, _workout_ids), do: {:error, :organization_context_required}

  # Each id becomes `%{id, original, fresh?}`: WODs the class already has
  # are kept; new ones are filed in the day's folder.
  defp file_new(context, slot, workout_ids) do
    current = ClassWorkouts.ids(slot)

    if Enum.all?(workout_ids, &(&1 in current)) do
      {:ok, Enum.map(workout_ids, &%{id: &1, original: &1, filed: nil})}
    else
      with {:ok, folder} <- WorkoutLibraryFolders.class_day_folder(context, slot.scheduled_at) do
        Enum.reduce_while(workout_ids, {:ok, []}, fn workout_id, {:ok, acc} ->
          if workout_id in current do
            {:cont, {:ok, [%{id: workout_id, original: workout_id, filed: nil} | acc]}}
          else
            case FileWorkoutCopy.ensure_in_folder(context, workout_id, folder.id,
                   reuse_copy: true
                 ) do
              {:ok, filed} ->
                {:cont, {:ok, [%{id: filed.id, original: workout_id, filed: filed} | acc]}}

              error ->
                Enum.each(acc, &discard(context, &1))
                {:halt, error}
            end
          end
        end)
        |> case do
          {:ok, list} -> {:ok, Enum.reverse(list)}
          error -> error
        end
      end
    end
  end

  defp discard(_context, %{filed: nil}), do: :ok

  defp discard(context, %{filed: filed, original: original}),
    do: FileWorkoutCopy.discard(context, filed, original)

  defp announce(slot) do
    ScheduleRealtime.broadcast("class_workouts_changed", %{
      organization_id: slot.organization_id,
      slot_id: slot.id
    })
  end
end
