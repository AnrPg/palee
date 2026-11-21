defmodule Palee.Workouts.OrganizationWorkoutKind do
  @moduledoc """
  ADR-690: a box's own workout type, `box:<id>` on its WODs. The label is
  shown as typed in every language; the family feeds stats, badges and
  colours. `merged` keeps the row so old references (a member's training
  log) still resolve through `merged_into`.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_workout_kinds" do
    field :organization_id, :binary_id
    field :label, :string
    field :folded, :string
    field :family, :string
    field :status, :string, default: "active"
    field :merged_into, :string
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end
end
