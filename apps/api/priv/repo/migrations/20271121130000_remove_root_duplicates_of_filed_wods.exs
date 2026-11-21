defmodule Palee.Repo.Migrations.RemoveRootDuplicatesOfFiledWods do
  @moduledoc """
  ADR-680 (ANR chose «Αυτόματο καθάρισμα», 2026-11-21): before ADR-680 a WOD
  made with «+ Νέο WOD» for a day, class, athlete or member stayed at the
  library root while a copy of it was filed in that thing's folder. This
  removes those root originals, keeping the filed copy.

  A root WOD is removed only when all of this holds, so library templates are
  never touched:

    * it is a published, shared WOD at the library root, not a benchmark;
    * exactly one WOD was copied from it, and that copy sits in a system
      folder (`classes:<date>`, `athlete:<id>`, `member_variations:<id>`);
    * the copy was made within a day after it, and it was not edited after
      the copy was made;
    * nothing else uses it: no class, series, day WOD, assignment, log,
      execution, snapshot, plan set, scaling suggestion or programme.

  Its WOD goals move to the copy first (the copy inherited them, ADR-163)
  when the copy has none of its own. Deleting it clears the copy's
  `source_workout_id`. Irreversible: `down` does nothing.
  """

  use Ecto.Migration

  def up do
    execute("DROP TABLE IF EXISTS adr680_root_duplicates")

    execute("""
    CREATE TEMP TABLE adr680_root_duplicates ON COMMIT DROP AS
    SELECT root.id AS root_id, (array_agg(copy.id))[1] AS copy_id
    FROM master_workouts AS root
    JOIN master_workouts AS copy ON copy.source_workout_id = root.id
    WHERE root.folder_id IS NULL
      AND root.status = 'published'
      AND root.library_visibility = 'shared'
      AND root.benchmark_key IS NULL
    GROUP BY root.id, root.inserted_at, root.updated_at
    HAVING count(*) = 1
      AND bool_and(
        copy.inserted_at >= root.inserted_at
        AND copy.inserted_at <= root.inserted_at + interval '1 day'
        AND root.updated_at <= copy.inserted_at + interval '1 minute'
        AND EXISTS (
          SELECT 1 FROM workout_folders AS f
          WHERE f.id = copy.folder_id
            AND (f.system_key LIKE 'classes:____-__-__'
              OR f.system_key LIKE 'athlete:%'
              OR f.system_key LIKE 'member_variations:%')
        )
      )
    """)

    execute("""
    DELETE FROM adr680_root_duplicates AS d
    WHERE EXISTS (SELECT 1 FROM scheduled_classes WHERE master_workout_id = d.root_id)
       OR EXISTS (SELECT 1 FROM class_series WHERE master_workout_id = d.root_id)
       OR EXISTS (SELECT 1 FROM day_workouts WHERE master_workout_id = d.root_id)
       OR EXISTS (SELECT 1 FROM assigned_workouts WHERE master_workout_id = d.root_id)
       OR EXISTS (SELECT 1 FROM training_log_entries WHERE master_workout_id = d.root_id)
       OR EXISTS (SELECT 1 FROM workout_executions WHERE master_workout_id = d.root_id)
       OR EXISTS (SELECT 1 FROM workout_snapshots WHERE master_workout_id = d.root_id)
       OR EXISTS (SELECT 1 FROM execution_plan_sets WHERE master_workout_id = d.root_id)
       OR EXISTS (SELECT 1 FROM scaling_suggestions WHERE master_workout_id = d.root_id)
       OR EXISTS (SELECT 1 FROM programme_versions WHERE days::text LIKE '%' || d.root_id::text || '%')
       OR EXISTS (SELECT 1 FROM programmes WHERE draft_days::text LIKE '%' || d.root_id::text || '%')
    """)

    execute("""
    UPDATE workout_goals AS g
    SET master_workout_id = d.copy_id
    FROM adr680_root_duplicates AS d
    WHERE g.master_workout_id = d.root_id
      AND NOT EXISTS (SELECT 1 FROM workout_goals WHERE master_workout_id = d.copy_id)
    """)

    execute("""
    DELETE FROM master_workouts
    WHERE id IN (SELECT root_id FROM adr680_root_duplicates)
    """)
  end

  def down, do: :ok
end
