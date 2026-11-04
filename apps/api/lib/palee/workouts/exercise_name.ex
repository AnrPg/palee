defmodule Palee.Workouts.ExerciseName do
  @moduledoc """
  ADR-461: an exercise name someone typed, kept for suggestions. A `user`
  row is a person's own name (training log, PRs), seen only by them; an
  `org` row is a name from a box's published WODs, seen by its members.
  `folded` is the match key (`ExerciseNames.fold/1`); `catalog_slug` links
  the Palee catalog entry when there is one. Row-level security keeps each
  scope to its owner.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "exercise_names" do
    field :scope, :string
    field :user_id, :binary_id
    field :organization_id, :binary_id
    field :name, :string
    field :folded, :string
    field :catalog_slug, :string
    field :uses_count, :integer, default: 0
    field :last_used_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
