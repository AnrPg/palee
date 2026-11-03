defmodule Palee.Repo.Migrations.PaleeWideBenchmarkLeaderboard do
  @moduledoc """
  ADR-394: the Palee-wide board of a benchmark WOD («Όλο το Palee»).

    * `master_workouts.benchmark_key`: the benchmark a coach tagged the WOD
      with (`Workouts.Domain.WorkoutBenchmarks`), or nothing. Never guessed
      from the title.
    * `palee_leaderboard_consents`: a person's own answer to «Να μπει το
      σκορ σου στον πίνακα όλου του Palee;» — `share` (others see their
      nickname, box and score) or `see_only` (they see the board and their
      own place, nobody sees them). Account level, separate from each box's
      opt-in (`leaderboard_opt_ins`); only its owner reads or writes it.
      Withdrawing deletes the row.
    * Two narrow SECURITY DEFINER functions (ADR-131 §2, like the
      `palee_around_*` ones) answer the one cross-box question. Results stay
      in their boxes' tables under forced RLS; the functions return only:
        - `palee_benchmark_results`: per result of a WOD tagged with the
          benchmark, kept in a box (a published, non-personal WOD), finished,
          not voided and not kept `private`, from people who chose `share`
          (and the caller's own, when the caller answered at all): an opaque
          person reference, whether it is the caller, nickname, box name,
          scale level, division and age group (from that box's opt-in row),
          the WOD's id and its section scores;
        - `palee_benchmark_workout_sections`: for those WODs only, which of
          their sections is scored (id, order, name, scoreable, score
          config) so the application ranks by the same section as the box
          board.
      Both refuse a caller without `app.user_id`. They pin only
      `search_path`.
  """

  use Ecto.Migration

  def up do
    alter table(:master_workouts) do
      add :benchmark_key, :string, size: 40
    end

    create index(:master_workouts, [:benchmark_key],
             where: "benchmark_key IS NOT NULL",
             name: :master_workouts_benchmark_key_index
           )

    create table(:palee_leaderboard_consents, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :choice, :string, size: 16, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:palee_leaderboard_consents, :palee_leaderboard_consents_choice_check,
             check: "choice IN ('share', 'see_only')"
           )

    owner = "user_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

    execute("""
    CREATE POLICY palee_leaderboard_consents_owner_policy ON palee_leaderboard_consents
    FOR ALL USING (#{owner}) WITH CHECK (#{owner})
    """)

    execute("ALTER TABLE palee_leaderboard_consents ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE palee_leaderboard_consents FORCE ROW LEVEL SECURITY")

    definer = "LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp"

    execute("""
    CREATE FUNCTION palee_benchmark_results(
      p_key text, p_from timestamp, p_to timestamp, p_year integer
    )
    RETURNS TABLE (
      person_ref text, is_viewer boolean, nickname text, box_name text, workout_id uuid,
      scale_level_slug text, division text, age_group text, section_scores jsonb
    )
    #{definer}
    AS $$
      WITH viewer AS (
        SELECT NULLIF(current_setting('app.user_id', true), '')::uuid AS id
      ),
      tagged AS (
        SELECT w.id, w.organization_id
        FROM master_workouts w
        WHERE w.benchmark_key = p_key
          AND w.status = 'published'
          AND w.library_visibility <> 'personal'
          AND w.organization_id IS NOT NULL
      ),
      results AS (
        SELECT e.user_id, e.organization_id, e.master_workout_id, e.scale_level_slug,
               e.section_scores
        FROM workout_executions e
        JOIN tagged t ON t.id = e.master_workout_id AND t.organization_id = e.organization_id
        WHERE e.completed_at_utc IS NOT NULL
          AND e.completed_at_utc >= p_from AND e.completed_at_utc < p_to
          AND e.journal_visibility <> 'private'
        UNION ALL
        SELECT l.user_id, l.organization_id, l.master_workout_id, l.scale_level_slug,
               l.section_scores
        FROM training_log_entries l
        JOIN tagged t ON t.id = l.master_workout_id AND t.organization_id = l.organization_id
        WHERE l.status <> 'voided'
          AND l.performed_at_utc >= p_from AND l.performed_at_utc < p_to
          AND l.journal_visibility <> 'private'
      )
      SELECT md5(r.user_id::text || ':' || p_key),
             r.user_id = v.id,
             u.nickname::text,
             o.name::text,
             r.master_workout_id,
             r.scale_level_slug::text,
             lo.division::text,
             CASE
               WHEN lo.birth_year IS NULL THEN NULL
               WHEN p_year - lo.birth_year < 18 THEN 'under_18'
               WHEN p_year - lo.birth_year < 35 THEN '18_34'
               WHEN p_year - lo.birth_year >= 65 THEN '65_plus'
               ELSE ((p_year - lo.birth_year) / 5 * 5)::text || '_' ||
                    ((p_year - lo.birth_year) / 5 * 5 + 4)::text
             END,
             to_jsonb(r.section_scores)
      FROM results r
      CROSS JOIN viewer v
      JOIN palee_leaderboard_consents c ON c.user_id = r.user_id
      JOIN users u ON u.id = r.user_id
      JOIN organizations o ON o.id = r.organization_id
      LEFT JOIN leaderboard_opt_ins lo
        ON lo.organization_id = r.organization_id AND lo.user_id = r.user_id
      WHERE v.id IS NOT NULL
        AND (c.choice = 'share' OR r.user_id = v.id)
    $$
    """)

    execute("""
    CREATE FUNCTION palee_benchmark_workout_sections(p_key text, p_workout_ids uuid[])
    RETURNS TABLE (workout_id uuid, authoring_mode text, sections jsonb)
    #{definer}
    AS $$
      SELECT w.id,
             w.authoring_mode::text,
             COALESCE(
               jsonb_agg(
                 jsonb_build_object(
                   'id', s.id, 'order', s."order", 'name', s.name,
                   'scoreable', s.scoreable, 'score_config', s.score_config
                 ) ORDER BY s."order", s.id
               ) FILTER (WHERE s.id IS NOT NULL),
               '[]'::jsonb
             )
      FROM master_workouts w
      LEFT JOIN workout_sections s
        ON s.master_workout_id = w.id AND s.organization_id = w.organization_id
      WHERE NULLIF(current_setting('app.user_id', true), '') IS NOT NULL
        AND w.id = ANY(p_workout_ids)
        AND w.benchmark_key = p_key
        AND w.status = 'published'
        AND w.library_visibility <> 'personal'
      GROUP BY w.id, w.authoring_mode
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_benchmark_workout_sections(text, uuid[])")

    execute(
      "DROP FUNCTION IF EXISTS palee_benchmark_results(text, timestamp, timestamp, integer)"
    )

    drop table(:palee_leaderboard_consents)
    drop index(:master_workouts, [:benchmark_key], name: :master_workouts_benchmark_key_index)

    alter table(:master_workouts) do
      remove :benchmark_key
    end
  end
end
