defmodule Palee.Application.ExecutionPacer do
  @moduledoc """
  «Ο προηγούμενος εαυτός σου» (ADR-374, CP-D7). Two use cases on the
  person's own execution:

    * `record_splits/3` – split marks from the timer (phone or watch, possibly
      late and repeated after being offline), checked against the
      execution's timer segments and stored once each;
    * `show/2` – the pace line of the previous attempt at the same WOD or
      benchmark next to this one, live while it runs and in the results.

  Only the person's own attempts are ever compared (vision §4.4).
  """

  alias Palee.Application.{Clock, ExecutionTimerSequence, ListWorkoutExecutions}
  alias Palee.Execution
  alias Palee.Execution.{ExecutionStore, SplitStore}

  @doc "`{:ok, %{stored, total}}`: how many marks were new and how many the execution has."
  def record_splits(%{user_id: user_id} = context, execution_id, params) do
    marks = Map.get(params, "marks") || Map.get(params, :marks)

    ExecutionStore.with_user_context(context, fn ->
      with {:ok, execution} <- own_execution(execution_id, user_id),
           segments = ExecutionTimerSequence.for_execution(execution),
           {:ok, rows} <- Execution.cast_split_marks(marks, segments),
           {:ok, stored} <- SplitStore.insert_splits(execution.id, user_id, rows, Clock.now()) do
        total =
          execution.id |> List.wrap() |> SplitStore.list_splits() |> Map.get(execution.id, [])

        {:ok, %{stored: stored, total: length(total)}}
      end
    end)
  end

  @doc "`{:ok, pacer}`; `pacer.previous` is nil when there is nothing to race."
  def show(%{user_id: user_id} = context, execution_id) do
    with {:ok, execution} <-
           ExecutionStore.with_user_context(context, fn ->
             own_execution(execution_id, user_id)
           end),
         {:ok, executions} <- ListWorkoutExecutions.call(context, user_id) do
      candidates = Enum.map(executions, &candidate/1)
      current = Enum.find(candidates, &(&1.id == execution.id)) || candidate(execution)
      previous = Execution.pick_previous_attempt(candidates, current)
      {:ok, pacer(context, execution, previous && Enum.find(executions, &(&1.id == previous.id)))}
    end
  end

  defp own_execution(execution_id, user_id) do
    case Execution.get_execution(execution_id) do
      %{user_id: ^user_id} = execution -> {:ok, execution}
      _other -> {:error, :not_found}
    end
  end

  defp candidate(execution) do
    %{
      id: execution.id,
      status: execution.status,
      started_at_utc: execution.started_at_utc,
      completed_at_utc: execution.completed_at_utc,
      scale_level_slug: execution.scale_level_slug,
      key:
        Execution.workout_identity(%{
          title: Map.get(execution, :workout_title),
          type: Map.get(execution, :workout_type),
          tags: Map.get(execution, :workout_tags, []),
          source_workout_id: Map.get(execution, :workout_source_id)
        })
    }
  end

  defp pacer(_context, execution, nil) do
    %{execution_id: execution.id, previous: nil, precision: nil, checkpoints: [], sections: []}
    |> Map.merge(%{ghost_total_ms: nil, current_total_ms: execution.total_elapsed_ms})
    |> Map.put(:total_delta_ms, nil)
  end

  defp pacer(context, execution, previous) do
    splits =
      SplitStore.with_context(context, fn ->
        SplitStore.list_splits([execution.id, previous.id])
      end)

    current_segments = ExecutionTimerSequence.for_execution(execution)

    previous_segments =
      if previous.master_workout_id == execution.master_workout_id and
           previous.scale_level_slug == execution.scale_level_slug,
         do: current_segments,
         else: ExecutionTimerSequence.for_execution(previous)

    ghost = side(previous, Map.get(splits, previous.id, []), previous_segments, true)

    current =
      side(
        execution,
        Map.get(splits, execution.id, []),
        current_segments,
        to_string(execution.status) == "completed"
      )

    ghost
    |> Execution.compare_pace(current, Execution.pace_section_names(current_segments))
    |> Map.merge(%{
      execution_id: execution.id,
      previous: %{
        execution_id: previous.id,
        completed_at_utc: previous.completed_at_utc,
        completed_at_tz: previous.completed_at_tz,
        scale_level_slug: previous.scale_level_slug,
        same_workout: previous.master_workout_id == execution.master_workout_id
      }
    })
  end

  defp side(execution, splits, segments, completed?) do
    %{
      checkpoints: Execution.pace_checkpoints(splits),
      section_times:
        Execution.pace_section_times(
          execution.section_elapsed_ms || %{},
          Execution.split_section_ordinals(segments)
        ),
      total_ms: execution.total_elapsed_ms,
      completed?: completed?
    }
  end
end
