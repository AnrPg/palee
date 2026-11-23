defmodule Palee.Scheduling.ScheduledClassWorkout do
  @moduledoc """
  ADR-746: one more WOD of a class, after its first one
  (`scheduled_classes.master_workout_id`). `position` starts at 1.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "scheduled_class_workouts" do
    field :organization_id, :binary_id
    field :scheduled_class_id, :binary_id
    field :master_workout_id, :binary_id
    field :position, :integer

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(row \\ %__MODULE__{}, params) do
    row
    |> cast(params, [:organization_id, :scheduled_class_id, :master_workout_id, :position])
    |> validate_required([:organization_id, :scheduled_class_id, :master_workout_id, :position])
    |> validate_number(:position, greater_than_or_equal_to: 1)
    |> foreign_key_constraint(:master_workout_id)
    |> unique_constraint([:scheduled_class_id, :master_workout_id],
      name: :scheduled_class_workouts_once_index
    )
  end
end
