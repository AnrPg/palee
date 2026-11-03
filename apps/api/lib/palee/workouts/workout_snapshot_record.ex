defmodule Palee.Workouts.WorkoutSnapshotRecord do
  @moduledoc "ADR-357: one stored snapshot of a WOD's content (`workout_snapshots`)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workout_snapshots" do
    field :organization_id, :binary_id
    field :master_workout_id, :binary_id
    field :content_hash, :string
    field :format_version, :integer, default: 1
    field :title, :string
    field :content, :map

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(record \\ %__MODULE__{}, params) do
    record
    |> cast(params, [
      :organization_id,
      :master_workout_id,
      :content_hash,
      :format_version,
      :title,
      :content
    ])
    |> validate_required([:organization_id, :master_workout_id, :content_hash, :content])
    |> validate_length(:content_hash, is: 64)
    |> unique_constraint([:organization_id, :master_workout_id, :content_hash],
      name: :workout_snapshots_content_index
    )
  end
end
