defmodule Palee.Repo.Migrations.WorkoutSnapshots do
  @moduledoc """
  ADR-357 (CP-D3): the WOD exactly as it was when it was assigned to an
  athlete or performed.

    * `workout_snapshots` – content-addressed: one row per distinct content
      of a WOD (`content_hash`, SHA-256 of its canonical form), so a WOD
      that never changes has one snapshot however often it is used;
    * `workout_snapshot_id` on `assigned_workouts` (written when the WOD is
      assigned), `workout_executions` (when the run is completed) and
      `training_log_entries` (when the score is logged).

  `master_workout_id` carries no foreign key: a snapshot outlives the WOD
  it was taken from, which is the point of it.
  """

  use Ecto.Migration

  def up do
    create table(:workout_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :master_workout_id, :binary_id, null: false
      add :content_hash, :string, size: 64, null: false
      add :format_version, :integer, null: false, default: 1
      add :title, :string
      add :content, :map, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:workout_snapshots, [:organization_id, :master_workout_id, :content_hash],
             name: :workout_snapshots_content_index
           )

    create index(:workout_snapshots, [:master_workout_id, :inserted_at])

    execute("""
    CREATE TRIGGER workout_snapshots_apply_tenant_context
    BEFORE INSERT OR UPDATE ON workout_snapshots
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY workout_snapshots_tenant_policy ON workout_snapshots
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE workout_snapshots ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE workout_snapshots FORCE ROW LEVEL SECURITY")

    for table <- [:assigned_workouts, :workout_executions, :training_log_entries] do
      alter table(table) do
        add :workout_snapshot_id,
            references(:workout_snapshots, type: :binary_id, on_delete: :nilify_all)
      end

      create index(table, [:workout_snapshot_id], where: "workout_snapshot_id IS NOT NULL")
    end
  end

  def down do
    for table <- [:assigned_workouts, :workout_executions, :training_log_entries] do
      alter table(table) do
        remove :workout_snapshot_id
      end
    end

    drop table(:workout_snapshots)
  end
end
