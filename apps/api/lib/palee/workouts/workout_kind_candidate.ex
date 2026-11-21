defmodule Palee.Workouts.WorkoutKindCandidate do
  @moduledoc """
  ADR-690: one name in the Palee team's queue, folded across boxes: the
  boxes that made it a type, the families they chose, and the public page's
  discipline suggestions with the same name. The decision is its audit
  trail. Holds no person besides the deciding Palee team member.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workout_kind_candidates" do
    field :label, :string
    field :folded, :string
    field :family_votes, :map, default: %{}
    field :organization_ids, {:array, :binary_id}, default: []
    field :profile_suggestion_ids, {:array, :binary_id}, default: []
    field :status, :string, default: "pending"
    field :decision, :map
    field :first_seen_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :digested_at, :utc_datetime_usec
    field :decided_at, :utc_datetime_usec
    field :decided_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end
end
