defmodule Palee.Application.ClassWorkoutFiling do
  @moduledoc """
  Files the workout of a dated class in `Classes/<year>/<month>/<date>`.

  Filing happens only when a workout is *assigned* to an existing class (or a
  class's workout is changed). Creating classes never files anything, so the
  Classes tree only holds days that actually had a workout programmed, instead
  of filling up with placeholder copies for every scheduled class.

  The class gets its own copy in that day's folder, leaving the template
  untouched. A workout already filed in the day's folder (e.g. created
  specifically for the class) is used as-is, and classes on the same day share
  one copy.
  """

  alias Palee.Application.{FileWorkoutCopy, WorkoutLibraryFolders}
  alias Palee.Workouts

  @doc """
  Runs `persist.(context, params)` with `master_workout_id` swapped for the
  filed workout, and discards a fresh copy if persisting fails. Nothing is
  filed when the workout is unchanged from `current_workout_id`.
  """
  def with_filed_workout(context, params, persist, current_workout_id \\ nil) do
    workout_id = value(params, :master_workout_id)

    if is_nil(workout_id) or workout_id == current_workout_id do
      persist.(context, params)
    else
      case WorkoutLibraryFolders.class_day_folder(context, value(params, :scheduled_at)) do
        {:ok, folder} -> file_and_persist(context, params, persist, workout_id, folder.id)
        # Let slot validation report a missing or malformed time.
        {:error, :invalid_scheduled_at} -> persist.(context, params)
        error -> error
      end
    end
  end

  @doc """
  ADR-680: creating a class files nothing, except a WOD made for that class
  («+ Νέο WOD» in the class form), which moves into the class's day folder so
  it never stays at the library root.
  """
  def with_class_made_workout(context, params, persist) do
    if made_for_it?(context, value(params, :master_workout_id)),
      do: with_filed_workout(context, params, persist),
      else: persist.(context, params)
  end

  defp made_for_it?(context, workout_id) when is_binary(workout_id) and workout_id != "",
    do: match?(%{awaiting_filing: true}, Workouts.get_workout_for_admin(context, workout_id))

  defp made_for_it?(_context, _none), do: false

  defp file_and_persist(context, params, persist, workout_id, folder_id) do
    with {:ok, filed} <-
           FileWorkoutCopy.ensure_in_folder(context, workout_id, folder_id, reuse_copy: true) do
      context
      |> persist.(put_value(params, :master_workout_id, filed.id))
      |> case do
        {:ok, result} ->
          {:ok, result}

        error ->
          FileWorkoutCopy.discard(context, filed, workout_id)
          error
      end
    end
  end

  defp value(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp put_value(map, key, value) do
    if Map.has_key?(map, Atom.to_string(key)),
      do: Map.put(map, Atom.to_string(key), value),
      else: Map.put(map, key, value)
  end
end
