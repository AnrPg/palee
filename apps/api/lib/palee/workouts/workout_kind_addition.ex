defmodule Palee.Workouts.WorkoutKindAddition do
  @moduledoc "ADR-690: a workout kind the Palee team added for everyone, with a label per locale."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workout_kind_additions" do
    field :key, :string
    field :family, :string
    field :labels, :map
    field :candidate_id, :binary_id
    field :added_by_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
