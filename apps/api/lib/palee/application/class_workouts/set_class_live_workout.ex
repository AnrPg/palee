defmodule Palee.Application.ClassWorkouts.SetClassLiveWorkout do
  @moduledoc """
  ADR-746: the coach's «Τώρα» among a class's WODs. People who will decide
  at the box follow it on their phones; the class timer and box screens
  show it. The timer of the WOD left behind is not touched here: the coach
  remote decides whether it stops or keeps running (ADR-746 §3).
  """

  alias Palee.Application.{ClassTimerView, ScheduleRealtime}
  alias Palee.{Organizations, Scheduling}

  def call(%{organization_id: _} = context, slot_id, workout_id) do
    with %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found},
         :ok <- Organizations.authorize_location(context, Map.get(slot, :location_id)),
         {:ok, updated} <- Scheduling.set_live_workout(context, slot.id, blank_to_nil(workout_id)) do
      ScheduleRealtime.broadcast("class_live_workout_changed", %{
        organization_id: updated.organization_id,
        slot_id: updated.id
      })

      ClassTimerView.broadcast_current(context, updated.id)
      {:ok, updated}
    end
  end

  def call(_context, _slot_id, _workout_id), do: {:error, :organization_context_required}

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
