defmodule Palee.Workouts.Domain.WorkoutDsl.ExerciseCatalog do
  @moduledoc """
  Canonical exercise registry used by Quick Text resolution and
  autocomplete.

  ADR-560: the exercises and their aliases live in the reference tables
  (`exercises`, `exercise_aliases`), read through `Palee.Catalog.reference/0`;
  this module owns the Quick Text rule of which parameters each category
  takes. Identifiers are stable slugs. Labels and aliases may evolve, but an
  existing identifier is never reassigned to another movement.
  """

  @strength_capabilities ~w(
    sets reps load target-rpe target-rir tempo side stance grip
    range-of-motion equipment rest progression percentage-of variation
    interval-assignment score-contribution transition-time
  )
  @bodyweight_capabilities ~w(
    sets reps duration load target-rpe target-rir tempo side grip
    range-of-motion equipment rest progression percentage-of variation
    interval-assignment score-contribution transition-time
  )
  @cardio_capabilities ~w(
    sets duration distance calories pace cadence target-heart-rate incline
    resistance equipment rest interval-assignment variation score-contribution
    transition-time
  )
  @mobility_capabilities ~w(
    sets reps duration side range-of-motion equipment rest target-rpe variation
    interval-assignment score-contribution transition-time
  )
  @skill_capabilities ~w(
    sets reps duration target-rpe tempo side grip range-of-motion equipment
    rest progression interval-assignment variation score-contribution
    transition-time
  )

  @capabilities %{
    "strength" => @strength_capabilities,
    "bodyweight" => @bodyweight_capabilities,
    "cardio" => @cardio_capabilities,
    "mobility" => @mobility_capabilities,
    "skill" => @skill_capabilities
  }

  alias Palee.Catalog.Domain.Reference

  @doc "Every exercise (`%{id, label, category, origin, aliases, capabilities}`), in catalog order."
  def entries, do: Palee.Catalog.reference().exercises

  @doc "The Quick Text parameters an exercise of `category` takes."
  def capabilities_for(category), do: Map.get(@capabilities, category, [])

  @doc "ADR-461: the entry's search-only aliases (suggestions match them, `resolve/1` does not)."
  def search_aliases(id), do: Reference.search_aliases(Palee.Catalog.reference(), id)

  def resolve(name), do: Reference.resolve(Palee.Catalog.reference(), name)

  def fetch(id), do: Reference.fetch_exercise(Palee.Catalog.reference(), id)

  def supports?(entry_or_id, capability) do
    entry =
      if is_map(entry_or_id),
        do: entry_or_id,
        else: fetch(to_string(entry_or_id))

    is_map(entry) and to_string(capability) in entry.capabilities
  end

  def export do
    Enum.map(entries(), &Map.take(&1, [:id, :label, :category, :aliases, :capabilities]))
  end
end
