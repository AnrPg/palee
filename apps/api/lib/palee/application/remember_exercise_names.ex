defmodule Palee.Application.RememberExerciseNames do
  @moduledoc """
  ADR-461: the queued work of a saved training-log entry, PR or published
  WOD. Its names are linked to the Palee catalog (built-in entries and
  approved additions) where they are one of its labels or aliases, and are
  remembered for their owner, so they show in the owner's own group at
  once, unverified. A name that matched nothing is counted as a candidate
  for the Palee team's review (`ExerciseCatalogReview`); only an approved
  candidate ever reaches the «Palee» group.
  """

  alias Palee.Application.ExerciseNameIndex
  alias Palee.Workouts

  def call(owner, rows, increment, now \\ DateTime.utc_now()) do
    catalog = Workouts.exercise_catalog_documents()
    entries = Workouts.exercise_name_entries(rows, catalog)

    with {:ok, new} <- ExerciseNameIndex.record(owner, entries, increment) do
      new = MapSet.new(new)

      entries
      |> Enum.filter(&is_nil(&1.catalog_slug))
      |> Enum.map(&Map.put(&1, :new_owner?, MapSet.member?(new, &1.folded)))
      |> Workouts.note_exercise_name_candidates(now)
    end
  end
end
