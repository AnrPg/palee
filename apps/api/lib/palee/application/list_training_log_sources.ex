defmodule Palee.Application.ListTrainingLogSources do
  @moduledoc """
  Source picker for the "Log a workout" flow (ADR-118).

  Offers, for the acting user inside the tenant:

    * classes from the last 30 days the member held an approved booking for
      and that have already started
    * assignments scheduled in the last 30 days that were not rejected
    * published library workouts (staff, or a package with the library)

  Classes and assignments already logged, or already counted by a completed
  execution, are filtered out. Freeform logging is always available.

  ADR-451: `available_sources` names the source types this person may use,
  from their role and package (`TrainingLogSourcePolicy`); a list is empty
  whenever its type is not available.
  """

  alias Palee.{Execution, Scheduling, Workouts}
  alias Palee.Application.TrainingLogSourceAccess
  alias Palee.Execution.Domain.TrainingLogSourcePolicy

  @lookback_days 30
  @library_limit 100

  def call(%{organization_id: _} = context, %{id: user_id}) do
    now = DateTime.utc_now()
    facts = TrainingLogSourceAccess.package_facts(context, user_id)

    Execution.with_training_log_context(context, fn ->
      executions = Execution.list_executions_for_user(user_id)

      classes =
        context
        |> class_candidates(user_id, now)
        |> Execution.loggable_training_sources(
          Execution.list_logged_training_source_ids(user_id, "class"),
          executions
        )

      assignments =
        context
        |> assignment_candidates(user_id, DateTime.to_date(now))
        |> Execution.loggable_training_sources(
          Execution.list_logged_training_source_ids(user_id, "assigned_workout"),
          executions
        )

      library = if facts.library_access?, do: library_workouts(context), else: []

      available =
        TrainingLogSourcePolicy.available(
          Map.merge(facts, %{
            classes_to_log?: classes != [],
            assignments_to_log?: assignments != [],
            library_published?: library != []
          })
        )

      {:ok,
       %{
         available_sources: available,
         classes: only_if(available, "class", classes),
         assignments: only_if(available, "assigned_workout", assignments),
         library_workouts: only_if(available, "library_workout", library)
       }}
    end)
  end

  def call(_context, _actor), do: {:error, :organization_context_required}

  defp class_candidates(context, user_id, now) do
    context
    |> Scheduling.list_member_slots(user_id, DateTime.add(now, -@lookback_days * 86_400), now)
    |> case do
      slots when is_list(slots) -> slots
      _error -> []
    end
    |> Enum.filter(&(to_string(get_in(&1, [:user_booking, :status])) == "approved"))
    |> Enum.map(fn slot ->
      workout = slot.master_workout_id && Workouts.get_workout(context, slot.master_workout_id)

      %{
        source_type: "class",
        id: slot.id,
        booking_id: slot.user_booking.id,
        title:
          slot[:name] || (slot[:class_type] && slot.class_type.name) || workout_title(workout),
        scheduled_at: slot.scheduled_at,
        workout_id: workout && workout.id,
        workout_title: workout_title(workout),
        scoreable_sections: Execution.training_log_scoreable_sections(workout)
      }
    end)
    |> Enum.reverse()
  end

  defp assignment_candidates(context, user_id, today) do
    context
    |> Workouts.list_assigned_workouts_for_athlete(
      user_id,
      Date.add(today, -@lookback_days),
      today
    )
    |> case do
      assignments when is_list(assignments) -> assignments
      _error -> []
    end
    |> Enum.reject(&(&1[:my_athlete_status] == "rejected"))
    |> Enum.reject(&(&1[:execution_status] == "completed"))
    |> Enum.map(fn assignment ->
      workout = Workouts.get_workout(context, assignment.master_workout_id)

      %{
        source_type: "assigned_workout",
        id: assignment.id,
        title: workout_title(workout) || get_in(assignment, [:workout, :title]),
        scheduled_for: assignment.scheduled_for,
        workout_id: assignment.master_workout_id,
        workout_title: workout_title(workout),
        scoreable_sections: Execution.training_log_scoreable_sections(workout)
      }
    end)
    |> Enum.reverse()
  end

  defp only_if(available, type, items) do
    if type in available, do: Enum.map(items, &Map.delete(&1, :source_type)), else: []
  end

  defp library_workouts(context) do
    context
    |> Workouts.list_workouts()
    |> case do
      workouts when is_list(workouts) -> workouts
      _error -> []
    end
    |> Enum.filter(&(&1.status == "published"))
    |> Enum.take(@library_limit)
    |> Enum.map(&%{id: &1.id, title: &1.title, workout_type: &1.type})
  end

  defp workout_title(nil), do: nil
  defp workout_title(workout), do: workout.title
end
