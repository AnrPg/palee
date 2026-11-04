defmodule Palee.Repo.Migrations.CreateExerciseNames do
  @moduledoc """
  ADR-461: exercise names are free text with suggestions.

  - `exercise_names`: the names people typed, for «Έχεις γράψει» (scope
    `user`, a person's training log and PRs, only theirs) and «Του box σου»
    (scope `org`, the exercise names of a box's published WODs, for its
    members). `folded` is the match key; a GIN trigram index serves the
    Postgres fallback search, which runs when Meilisearch is unreachable.
    Row-level security: a `user` row is its owner's, an `org` row its
    organization's.
  - `user_pr_records.exercise_ref`: a PR picked from a Palee suggestion keeps
    its catalog slug next to the typed name, so analytics can count it.
  - The verified way the catalog grows: `exercise_name_candidates` (typed
    names that matched no catalog entry, counted and deduplicated by folded
    form, holding no person), `exercise_catalog_additions` (what the Palee
    team approved: a new entry or an alias of one) and the append-only
    `exercise_catalog_audit_events`. Platform tables, written and read only
    through the vendor console's endpoints; no row-level security, like the
    other platform queues (food_barcode_misses).
  - Backfill from existing PRs, training-log entries and published WODs.
    The fold here (lowercase, Greek and Latin accents translated away, spaces
    collapsed) matches `ExerciseNames.fold/1` for those letters; a rarer
    accent only costs a second row, merged by the next save.

  No function is created, and no extension setting is pinned anywhere (the
  production migration role is no superuser).
  """

  use Ecto.Migration

  @accented "άέήίόύώϊϋΐΰςàáâäãåèéêëìíîïòóôöõùúûüýÿçñ"
  @plain "αεηιουωιυιυσaaaaaaeeeeiiiiooooouuuuyycn"

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    create table(:exercise_names, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scope, :text, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
      add :name, :text, null: false
      add :folded, :text, null: false
      add :catalog_slug, :text
      add :uses_count, :integer, null: false, default: 0
      add :last_used_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:exercise_names, :exercise_names_scope_owner_check,
             check: """
             (scope = 'user' AND user_id IS NOT NULL AND organization_id IS NULL)
             OR (scope = 'org' AND organization_id IS NOT NULL AND user_id IS NULL)
             """
           )

    create constraint(:exercise_names, :exercise_names_name_length_check,
             check: "char_length(name) BETWEEN 1 AND 120 AND char_length(folded) >= 1"
           )

    create unique_index(:exercise_names, [:user_id, :folded],
             where: "scope = 'user'",
             name: :exercise_names_user_folded_index
           )

    create unique_index(:exercise_names, [:organization_id, :folded],
             where: "scope = 'org'",
             name: :exercise_names_org_folded_index
           )

    execute("""
    CREATE INDEX exercise_names_folded_trgm_index
      ON exercise_names USING gin (folded gin_trgm_ops)
    """)

    me = "NULLIF(current_setting('app.user_id', true), '')::uuid"
    org = "NULLIF(current_setting('app.organization_id', true), '')::uuid"

    execute("""
    CREATE POLICY exercise_names_user_policy ON exercise_names
    FOR ALL USING (scope = 'user' AND user_id = #{me})
    WITH CHECK (scope = 'user' AND user_id = #{me})
    """)

    execute("""
    CREATE POLICY exercise_names_org_policy ON exercise_names
    FOR ALL USING (scope = 'org' AND organization_id = #{org})
    WITH CHECK (scope = 'org' AND organization_id = #{org})
    """)

    execute("ALTER TABLE exercise_names ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE exercise_names FORCE ROW LEVEL SECURITY")

    alter table(:user_pr_records) do
      add :exercise_ref, :text
    end

    create constraint(:user_pr_records, :user_pr_records_exercise_ref_length_check,
             check: "exercise_ref IS NULL OR char_length(exercise_ref) <= 120"
           )

    create table(:exercise_name_candidates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false
      add :folded, :text, null: false
      add :uses_count, :integer, null: false, default: 0
      add :owners_count, :integer, null: false, default: 0
      add :status, :text, null: false, default: "pending"
      add :catalog_slug, :text
      add :first_seen_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :decided_at, :utc_datetime_usec
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:exercise_name_candidates, [:folded])
    create index(:exercise_name_candidates, [:status, :owners_count])

    create constraint(:exercise_name_candidates, :exercise_name_candidates_status_check,
             check: "status IN ('pending', 'approved', 'rejected')"
           )

    create table(:exercise_catalog_additions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :text, null: false
      add :catalog_slug, :text, null: false
      add :label, :text, null: false
      add :folded, :text, null: false
      add :category, :text

      add :candidate_id,
          references(:exercise_name_candidates, type: :binary_id, on_delete: :nilify_all)

      add :approved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:exercise_catalog_additions, :exercise_catalog_additions_kind_check,
             check: """
             (kind = 'entry' AND category IN ('strength', 'bodyweight', 'cardio', 'mobility', 'skill'))
             OR (kind = 'alias' AND category IS NULL)
             """
           )

    create unique_index(:exercise_catalog_additions, [:catalog_slug],
             where: "kind = 'entry'",
             name: :exercise_catalog_additions_entry_slug_index
           )

    create unique_index(:exercise_catalog_additions, [:folded],
             name: :exercise_catalog_additions_folded_index
           )

    create table(:exercise_catalog_audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :text, null: false
      add :actor_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :candidate_id,
          references(:exercise_name_candidates, type: :binary_id, on_delete: :nilify_all)

      add :catalog_slug, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:exercise_catalog_audit_events, [:inserted_at])

    create constraint(:exercise_catalog_audit_events, :exercise_catalog_audit_events_action_check,
             check: "action IN ('approve_entry', 'approve_alias', 'reject')"
           )

    backfill()
  end

  def down do
    drop table(:exercise_catalog_audit_events)
    drop table(:exercise_catalog_additions)
    drop table(:exercise_name_candidates)
    drop constraint(:user_pr_records, :user_pr_records_exercise_ref_length_check)

    alter table(:user_pr_records) do
      remove :exercise_ref
    end

    drop table(:exercise_names)
  end

  defp fold(column),
    do:
      "regexp_replace(btrim(translate(lower(#{column}), '#{@accented}', '#{@plain}')), '\\s+', ' ', 'g')"

  defp backfill do
    execute("""
    INSERT INTO exercise_names
      (id, scope, user_id, name, folded, catalog_slug, uses_count, last_used_at, inserted_at, updated_at)
    SELECT gen_random_uuid(), 'user', s.user_id,
      (array_agg(s.name ORDER BY s.used_at DESC))[1], s.folded, max(s.catalog_slug),
      count(*), max(s.used_at), now(), now()
    FROM (
      SELECT p.user_id, left(regexp_replace(btrim(p.name), '\\s+', ' ', 'g'), 120) AS name,
        #{fold("p.name")} AS folded, NULL::text AS catalog_slug, p.updated_at AS used_at
      FROM user_pr_records p
      UNION ALL
      SELECT e.user_id, left(regexp_replace(btrim(x->>'name'), '\\s+', ' ', 'g'), 120),
        #{fold("x->>'name'")}, NULLIF(x->>'exercise_ref', ''), e.updated_at
      FROM training_log_entries e, unnest(e.performed_exercises) AS x
      WHERE e.voided_at IS NULL
    ) s
    WHERE s.folded <> '' AND s.name <> ''
    GROUP BY s.user_id, s.folded
    ON CONFLICT DO NOTHING
    """)

    execute("""
    INSERT INTO exercise_names
      (id, scope, organization_id, name, folded, catalog_slug, uses_count, last_used_at, inserted_at, updated_at)
    SELECT gen_random_uuid(), 'org', s.organization_id,
      (array_agg(s.name ORDER BY s.used_at DESC))[1], s.folded, max(s.catalog_slug),
      count(DISTINCT s.workout_id), max(s.used_at), now(), now()
    FROM (
      SELECT w.organization_id, w.id AS workout_id,
        left(regexp_replace(btrim(x.name), '\\s+', ' ', 'g'), 120) AS name,
        #{fold("x.name")} AS folded, NULLIF(x.exercise_ref, '') AS catalog_slug, w.updated_at AS used_at
      FROM workout_exercises x
      JOIN workout_sections sec ON sec.id = x.workout_section_id
      JOIN master_workouts w ON w.id = sec.master_workout_id
      WHERE w.status = 'published' AND x.item_type = 'exercise' AND x.name IS NOT NULL
    ) s
    WHERE s.folded <> '' AND s.name <> ''
    GROUP BY s.organization_id, s.folded
    ON CONFLICT DO NOTHING
    """)
  end
end
