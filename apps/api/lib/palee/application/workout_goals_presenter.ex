defmodule Palee.Application.WorkoutGoalsPresenter do
  @moduledoc """
  Shapes WOD goals (ADR-163) for the staff editor, the member card and the
  «τι ένιωσες» checklist, and computes the live suggestion of a workout from
  its exercises. Shared by the goal use cases; no persistence of its own.
  """

  alias Palee.{Anatomy, Workouts}

  @doc """
  The deterministic suggestion for a workout: muscles with roles,
  qualities, how many of its exercises were recognised, and the taxonomy
  version it was computed with.
  """
  def suggestion(workout) do
    suggested = workout |> Workouts.goal_exercises() |> Anatomy.suggest_goals()

    %{
      muscles: Enum.map(suggested.muscles, &muscle/1),
      qualities: suggested.qualities,
      matched_exercises: suggested.matched_exercises,
      unmatched_exercises: suggested.unmatched_exercises,
      taxonomy_version: Anatomy.taxonomy_version()
    }
  end

  @doc """
  Staff view of a workout's goals, from `Workouts.resolve_workout_goals/2`:
  its own saved goals (`saved: true`); else those it inherits from the
  workout it was copied from (`saved: false`, `inherited_from` set); else
  the live suggestion, with the toggle at the gym's default.
  """
  def staff_goals(workout_id, resolved, suggestion, default_visible)

  def staff_goals(workout_id, %{goals: nil}, suggestion, default_visible) do
    %{
      workout_id: workout_id,
      saved: false,
      inherited_from: nil,
      muscles: suggestion.muscles,
      qualities: suggestion.qualities,
      stimulus: nil,
      visible_to_members: default_visible,
      source: "suggested",
      taxonomy_version: suggestion.taxonomy_version,
      updated_by_id: nil,
      updated_at: nil
    }
  end

  def staff_goals(workout_id, %{goals: saved, inherited_from: inherited_from}, _suggestion, _) do
    %{
      workout_id: workout_id,
      saved: is_nil(inherited_from),
      inherited_from: inherited_from,
      muscles: Enum.map(saved.muscles, &muscle/1),
      qualities: saved.qualities,
      stimulus: saved.stimulus,
      visible_to_members: saved.visible_to_members,
      source: saved.source,
      taxonomy_version: saved.taxonomy_version,
      updated_by_id: saved.updated_by_id,
      updated_at: saved.updated_at
    }
  end

  @doc """
  Member view of a workout's saved goals (its own or inherited): only
  goals the coach made visible, else nil. `workout_id` is the
  workout asked about, also when its goals are inherited.
  """
  def member_goals(workout_id, %{goals: %{visible_to_members: true} = saved}) do
    %{
      workout_id: workout_id,
      muscles: Enum.map(saved.muscles, &muscle/1),
      qualities: saved.qualities,
      stimulus: saved.stimulus,
      taxonomy_version: saved.taxonomy_version,
      updated_at: saved.updated_at
    }
  end

  def member_goals(_workout_id, _resolved), do: nil

  @doc """
  Member view of a workout's live suggestion, for a workout whose coach
  saved no goals (nil when nothing was recognised).
  """
  def suggested_member_goals(_workout_id, _workout, %{muscles: [], qualities: []}), do: nil

  def suggested_member_goals(workout_id, workout, suggestion) do
    %{
      workout_id: workout_id,
      muscles: suggestion.muscles,
      qualities: suggestion.qualities,
      stimulus: nil,
      taxonomy_version: suggestion.taxonomy_version,
      updated_at: utc(Map.get(workout, :updated_at) || Map.get(workout, :inserted_at))
    }
  end

  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp utc(at), do: at

  def muscle(%{id: id, role: role}), do: %{id: id, role: to_string(role)}
end
