defmodule Palee.Application.GetMemberWorkoutGoals do
  @moduledoc """
  A member's read of a published workout's WOD goals (ADR-163). The goals
  the coach saved, when switched visible; a workout without goals of its
  own (a class variant, a member version) shows the goals of the workout it
  was copied from, with their visibility. A workout whose coach saved
  nothing shows the live suggestion from its exercises, unless the gym
  switched `wod_goals_visible_by_default` off: the coach hides one workout's
  goals with its toggle, the gym hides every unsaved suggestion with the
  setting. Hidden and absent goals look the same to a member (`goals` nil).
  The workout must be a published workout of the member's gym (the same
  rule as reading the workout), else `:not_found`.
  """

  alias Palee.Application.WorkoutGoalsPresenter, as: Presenter
  alias Palee.{Organizations, Workouts}

  def call(context, workout_id) do
    with {:ok, workout_id} <- Ecto.UUID.cast(workout_id),
         %{} = workout <- Workouts.get_workout(context, workout_id) do
      {:ok, %{workout_id: workout_id, goals: visible(context, workout_id, workout)}}
    else
      _missing -> {:error, :not_found}
    end
  end

  @doc """
  The goals a member sees for `workout_id` in the context's gym, or nil.
  `workout` is read only when the suggestion is needed and not given.
  """
  def visible(context, workout_id, workout \\ nil) do
    case Workouts.resolve_workout_goals(context, workout_id) do
      %{goals: nil} ->
        if Organizations.get_workout_settings(context).wod_goals_visible_by_default,
          do: suggested(context, workout_id, workout),
          else: nil

      resolved ->
        Presenter.member_goals(workout_id, resolved)
    end
  end

  defp suggested(context, workout_id, nil) do
    case Workouts.get_workout(context, workout_id) do
      %{} = workout -> suggested(context, workout_id, workout)
      _missing -> nil
    end
  end

  defp suggested(_context, workout_id, workout),
    do: Presenter.suggested_member_goals(workout_id, workout, Presenter.suggestion(workout))
end
