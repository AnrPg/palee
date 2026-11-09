defmodule Palee.Anatomy.Domain.ExerciseTargets do
  @moduledoc """
  Which muscles a catalog exercise (`Workouts.Domain.WorkoutDsl.ExerciseCatalog`)
  trains and which fitness qualities it develops (ADR-163).

  ADR-560: the map lives in the `exercise_muscle_targets` and
  `exercise_quality_targets` reference tables (one role per muscle per
  exercise), read through `Palee.Catalog.reference/0`; the Palee team edits it
  in the vendor console. Keyed by the same stable ids as the injury-risk
  policy (ADR-124), so WOD goals, coverage and injury warnings reason about
  one exercise vocabulary.

  Roles:

    * `:primary` - the movement's prime movers
    * `:secondary` - synergists that do meaningful work
    * `:stabilizer` - muscles that hold position under load

  Targets name groups or heads of `MuscleTaxonomy`; a group means "the whole
  group" and rolls up the same way in coverage.
  """

  alias Palee.Catalog.Domain.Reference

  @doc "Catalog ids that have targets (an exercise nobody mapped yet has none)."
  def ids, do: Reference.targeted_ids(Palee.Catalog.reference())

  @doc """
  Targets of one catalog id: `%{muscles: [%{id, role}], qualities: [id]}`,
  strongest role first, or `nil` when the id is unknown or not mapped yet.
  """
  def fetch(catalog_id), do: Reference.targets(Palee.Catalog.reference(), catalog_id)

  @doc "Ordering weight of a role; higher is stronger."
  def role_rank(role), do: Reference.role_rank(role)

  def roles, do: Reference.roles()
end
