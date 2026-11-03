defmodule Palee.Application.UpdateExecutionProgress do
  @moduledoc """
  Saves a timer's progress. Since ADR-374's amendment (2026-11-03) it also
  stores the split marks the update implies (segments ended, AMRAP rounds
  counted), so every timer that saves progress feeds «Ο προηγούμενος εαυτός
  σου» without posting marks itself.
  """

  alias Palee.Application.Clock
  alias Palee.{Execution, Workouts}
  alias Palee.Execution.{ExecutionStore, SplitStore}

  def call(context, execution_id, user_id, params),
    do: ExecutionStore.with_user_context(context, fn -> call(execution_id, user_id, params) end)

  def call(execution_id, user_id, params) do
    with {:ok, current_execution} <- fetch_execution(execution_id, user_id),
         {:ok, segments} <- timer_sequence_for_execution(current_execution),
         {:ok, execution} <-
           Execution.update_execution_progress(
             execution_id,
             user_id,
             Map.put(params, :segments, segments)
           ) do
      record_implied_splits(current_execution, execution, segments)
      broadcast_progress_updated(execution)
      {:ok, execution}
    end
  end

  defp record_implied_splits(previous, execution, segments) do
    case Execution.split_marks_from_progress(previous, execution, segments) do
      [] -> :ok
      rows -> {:ok, _stored} = SplitStore.insert_splits(execution.id, execution.user_id, rows, Clock.now())
    end

    :ok
  end

  defp fetch_execution(execution_id, user_id) do
    case Execution.get_execution(execution_id) do
      nil -> {:error, :not_found}
      %{user_id: ^user_id} = execution -> {:ok, execution}
      %{} -> {:error, :forbidden}
    end
  end

  defp timer_sequence_for_execution(%{master_workout_id: nil}), do: {:ok, []}

  defp timer_sequence_for_execution(%{
         master_workout_id: workout_id,
         scale_level_slug: scale_slug,
         organization_id: organization_id,
         user_id: user_id
       }) do
    # The execution's own organization is the tenant that owns its workout.
    # This runs inside the outer ExecutionStore.with_user_context/2 wrap from
    # call/4, which - for the user-scoped /api/executions routes - never
    # carries an organization_id, so the workout lookup below would otherwise
    # silently see nothing (F-03 scoping) and this progress update would be
    # validated against zero timer segments.
    context = %{organization_id: organization_id, user_id: user_id}

    case resolve_workout(context, workout_id, scale_slug) do
      %{} = workout -> {:ok, Execution.build_timer_sequence(workout)}
      _missing -> {:ok, []}
    end
  end

  defp resolve_workout(context, workout_id, slug) when slug in [nil, ""],
    do: Workouts.get_workout(context, workout_id)

  defp resolve_workout(context, workout_id, scale_slug),
    do: Workouts.materialize_workout_for_scale(context, workout_id, scale_slug)

  defp broadcast_progress_updated(execution) do
    Phoenix.PubSub.broadcast(
      Palee.PubSub,
      "execution:progress_updated",
      {:execution_progress_updated, execution}
    )
  end
end
