defmodule Palee.Workouts.ExerciseNameCandidate do
  @moduledoc """
  ADR-461: a typed exercise name that matched nothing in the catalog,
  counted (uses, and owners who typed it) and deduplicated by folded form,
  waiting for the Palee team: approve it as a new catalog entry or as an
  alias of one, or reject it. Holds no person.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "exercise_name_candidates" do
    field :name, :string
    field :folded, :string
    field :uses_count, :integer, default: 0
    field :owners_count, :integer, default: 0
    field :status, :string, default: "pending"
    field :catalog_slug, :string
    field :first_seen_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :decided_at, :utc_datetime_usec
    field :decided_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end
end
