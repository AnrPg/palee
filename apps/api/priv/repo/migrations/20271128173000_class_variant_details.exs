defmodule Palee.Repo.Migrations.ClassVariantDetails do
  @moduledoc """
  ADR-785: a member's «Παραλλαγή» of one class (an assignment with
  `source_scheduled_class_id`, ADR-125) remembers where it came from.

    * `variant_of_workout_id`: the class WOD it stands in for (the member's
      pick, the coach's «Τώρα», or the class's first WOD). Its scores show
      under that WOD's leaderboard, marked «Παραλλαγή». A loose reference:
      removing the WOD from the class must not touch the variant.
    * `variant_source_hash`: the content hash (ADR-357) of that WOD when the
      variant was made or the coach chose «Κράτησέ τη». A different hash
      today means the class WOD changed after the variant.
    * `variant_set_aside_at`: the member went back to a WOD of the class
      instead (nil = the variant is what they do).
    * `assigned_by_user_id`: the staff member who made it («από coach …»).
  """

  use Ecto.Migration

  def change do
    alter table(:assigned_workouts) do
      add :variant_of_workout_id, :binary_id
      add :variant_source_hash, :text
      add :variant_set_aside_at, :utc_datetime_usec
      add :assigned_by_user_id, :binary_id
    end

    create index(:assigned_workouts, [:organization_id, :variant_of_workout_id, :scheduled_for],
             where: "variant_of_workout_id IS NOT NULL",
             name: :assigned_workouts_variant_of_index
           )
  end
end
