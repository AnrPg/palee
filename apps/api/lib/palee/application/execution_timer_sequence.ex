defmodule Palee.Application.ExecutionTimerSequence do
  @moduledoc """
  The timer segments an execution runs, read from its workout in the
  execution's own organization (the same resolution as progress updates),
  for split marks (ADR-374) and the watch plan (ADR-375).
  """

  alias Palee.{Execution, Workouts}

  @doc "The segments, or `[]` for a freeform execution or a deleted workout."
  def for_execution(%{master_workout_id: nil}), do: []

  def for_execution(%{master_workout_id: workout_id, organization_id: organization_id} = execution) do
    context = %{organization_id: organization_id, user_id: execution.user_id}

    case resolve_workout(context, workout_id, execution.scale_level_slug) do
      %{} = workout -> Execution.build_timer_sequence(workout)
      _missing -> []
    end
  end

  defp resolve_workout(%{organization_id: nil}, _workout_id, _slug), do: nil

  defp resolve_workout(context, workout_id, slug) when slug in [nil, ""],
    do: Workouts.get_workout(context, workout_id)

  defp resolve_workout(context, workout_id, scale_slug),
    do: Workouts.materialize_workout_for_scale(context, workout_id, scale_slug)
end
