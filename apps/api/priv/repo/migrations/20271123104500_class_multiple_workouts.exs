defmodule Palee.Repo.Migrations.ClassMultipleWorkouts do
  @moduledoc """
  ADR-746: a class (τμήμα) may hold more than one WOD.

    * `scheduled_class_workouts`: the class's WODs after its first one, in
      order (`position` 1, 2 …). The first WOD stays in
      `scheduled_classes.master_workout_id`, so every reader of "the class's
      WOD" keeps working and sees the first one. Like the first, a WOD a
      class uses cannot be deleted (restrict).
    * `scheduled_classes.live_workout_id`: the coach's «Τώρα» (nil = the
      first WOD). The class timer and box screens follow it.
    * `bookings.chosen_workout_id`: the WOD the person does (nil = «Θα
      αποφασίσω στο box», they follow the coach's «Τώρα»), who chose it and
      when (the member, or the coach for them).
    * `class_timers.master_workout_id`: one class timer per WOD, so one can
      keep running while another is shown. Existing timers belong to their
      class's first WOD.
  """

  use Ecto.Migration

  # ADR-746: another coach took a box screen that showed your class.
  @types ~w(box_screen_taken)

  def up do
    create table(:scheduled_class_workouts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :scheduled_class_id,
          references(:scheduled_classes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :master_workout_id,
          references(:master_workouts, type: :binary_id, on_delete: :restrict),
          null: false

      add :position, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:scheduled_class_workouts, :scheduled_class_workouts_position_check,
             check: "position >= 1"
           )

    create unique_index(:scheduled_class_workouts, [:scheduled_class_id, :master_workout_id],
             name: :scheduled_class_workouts_once_index
           )

    create unique_index(:scheduled_class_workouts, [:scheduled_class_id, :position],
             name: :scheduled_class_workouts_position_index
           )

    create index(:scheduled_class_workouts, [:master_workout_id])

    execute("""
    CREATE TRIGGER scheduled_class_workouts_apply_tenant_context
    BEFORE INSERT OR UPDATE ON scheduled_class_workouts
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY scheduled_class_workouts_tenant_policy ON scheduled_class_workouts
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE scheduled_class_workouts ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE scheduled_class_workouts FORCE ROW LEVEL SECURITY")

    alter table(:scheduled_classes) do
      add :live_workout_id,
          references(:master_workouts, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:bookings) do
      add :chosen_workout_id,
          references(:master_workouts, type: :binary_id, on_delete: :nilify_all)

      add :workout_chosen_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :workout_chosen_at, :utc_datetime_usec
    end

    create index(:bookings, [:chosen_workout_id], where: "chosen_workout_id IS NOT NULL")

    alter table(:class_timers) do
      add :master_workout_id,
          references(:master_workouts, type: :binary_id, on_delete: :delete_all)
    end

    flush()

    execute("""
    UPDATE class_timers t
    SET master_workout_id = c.master_workout_id
    FROM scheduled_classes c
    WHERE c.id = t.scheduled_class_id AND c.master_workout_id IS NOT NULL
    """)

    drop_if_exists unique_index(:class_timers, [:scheduled_class_id])

    execute("""
    CREATE UNIQUE INDEX class_timers_class_workout_index
      ON class_timers (scheduled_class_id, master_workout_id) NULLS NOT DISTINCT
    """)

    # Box screens (ANR picks 7A, 8A): a screen may follow a room of the
    # branch, choose how it shows classes that run together (`room`: the
    # class of its room, `split`: side by side), and a pin may name the WOD
    # it shows (nil = it follows the class's «Τώρα») or share the screen
    # with one more class this once.
    alter table(:box_screens) do
      add :space_id, :binary_id
      add :concurrent_mode, :string, null: false, default: "room"

      add :override_workout_id,
          references(:master_workouts, type: :binary_id, on_delete: :nilify_all)

      add :override_split_slot_id, :binary_id
    end

    execute("""
    ALTER TABLE box_screens
      ADD CONSTRAINT box_screens_space_fkey
      FOREIGN KEY (space_id, organization_id)
      REFERENCES spaces (id, organization_id)
      ON DELETE SET NULL (space_id)
    """)

    create constraint(:box_screens, :box_screens_concurrent_mode_check,
             check: "concurrent_mode IN ('room', 'split')"
           )

    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN (#{Enum.map_join(@types, ", ", &"'#{&1}'")})"
    )

    rewrite_notification_types(&(&1 -- @types))

    drop constraint(:box_screens, :box_screens_concurrent_mode_check)
    execute("ALTER TABLE box_screens DROP CONSTRAINT box_screens_space_fkey")

    alter table(:box_screens) do
      remove :space_id
      remove :concurrent_mode
      remove :override_workout_id
      remove :override_split_slot_id
    end

    execute("DROP INDEX IF EXISTS class_timers_class_workout_index")

    # Back to one timer per class: keep the first WOD's (or the one without WOD).
    execute("""
    DELETE FROM class_timers t
    USING scheduled_classes c
    WHERE c.id = t.scheduled_class_id
      AND t.master_workout_id IS DISTINCT FROM c.master_workout_id
    """)

    create unique_index(:class_timers, [:scheduled_class_id])

    alter table(:class_timers) do
      remove :master_workout_id
    end

    drop index(:bookings, [:chosen_workout_id])

    alter table(:bookings) do
      remove :chosen_workout_id
      remove :workout_chosen_by_id
      remove :workout_chosen_at
    end

    alter table(:scheduled_classes) do
      remove :live_workout_id
    end

    drop table(:scheduled_class_workouts)
  end

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = Regex.scan(~r/'([a-z0-9_]+)'/, definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{Enum.map_join(change.(current), ", ", &"'#{&1}'")}))"
    )
  end
end
