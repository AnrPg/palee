defmodule Palee.Application.GrowEditedGoals do
  @moduledoc """
  ADR-671: goals a coach edited by hand (`source: "edited"`) stop following
  the live suggestion, but new exercises in the text still reach them: what
  the suggestion gained since the goals were last reconciled
  (`suggestion_basis`) is folded in, only upwards (`Anatomy.merge_goals_up/2`:
  muscles added or promoted, qualities joined, nothing removed or demoted).
  A muscle the coach removed is in the basis, so it is never put back.

  Runs on every publish (whatever editor wrote the text, with or without the
  pre-publish exercise check) and after the coach answers that check
  (ADR-570). Goals the workout only inherits, or that follow the suggestion,
  are left alone. Goals saved before ADR-671 have no basis: the suggestion of
  the text before this edit (the published text; nothing for a first
  publish) stands in for it.
  """

  alias Palee.Anatomy
  alias Palee.Application.WorkoutGoalsPresenter, as: Presenter
  alias Palee.Workouts

  @doc """
  Grows the edited goals of `workout` (as the caller read it) from its
  current suggestion. `previous` is the workout as it was before this edit,
  read only for goals without a basis. Returns whether the goals changed.
  """
  def call(context, workout, previous \\ nil)

  def call(context, %{id: workout_id} = workout, previous) do
    case Workouts.get_workout_goals(context, workout_id) do
      %{source: "edited"} = saved -> grow(context, workout_id, saved, workout, previous)
      _suggested_inherited_or_none -> false
    end
  end

  def call(_context, _workout, _previous), do: false

  defp grow(context, workout_id, saved, workout, previous) do
    suggestion = Presenter.suggestion(workout)
    basis = saved.suggestion_basis || published_suggestion(previous || workout)
    merged = Anatomy.merge_goals_up(saved, Anatomy.goals_gained(basis, suggestion))
    changed? = not same?(merged, saved)
    new_basis = basis(suggestion)

    if changed? or saved.suggestion_basis != new_basis do
      {:ok, _goals} =
        Workouts.put_workout_goals(context, workout_id, %{
          muscles: merged.muscles,
          qualities: merged.qualities,
          stimulus: saved.stimulus,
          visible_to_members: saved.visible_to_members,
          source: "edited",
          taxonomy_version: Anatomy.taxonomy_version(),
          updated_by_id: if(changed?, do: context.user_id, else: saved.updated_by_id),
          suggestion_basis: new_basis
        })
    end

    changed?
  end

  @doc "ADR-671: the basis stored with goals: a suggestion's muscles and qualities."
  def basis(%{muscles: muscles, qualities: qualities}),
    do: %{muscles: Enum.map(muscles, &Presenter.muscle/1), qualities: qualities}

  # The text as published, without the coach's unpublished edit.
  defp published_suggestion(workout) do
    workout
    |> Map.put(:draft_data, nil)
    |> Map.delete("draft_data")
    |> Presenter.suggestion()
    |> basis()
  end

  defp same?(merged, saved),
    do:
      Enum.sort(merged.muscles) == Enum.sort(saved.muscles) and
        Enum.sort(merged.qualities) == Enum.sort(saved.qualities)
end
