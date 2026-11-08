defmodule Palee.Repo.Migrations.ProfileBoxWorkoutsProgress do
  @moduledoc """
  ADR-554 (amended 2026-11-08): the rest of the profile.

  - `community_profile_cards.box_id` / `show_rank`: the box the owner shows
    under «Λίγα λόγια» and whether their belt or level there shows with it.
    Both are off until the owner picks them.
  - Two more optional tabs, «Προπονήσεις» and «Πρόοδος».
  - Three definers answer the reader in one place, because the rows live in
    tables that only their owner (or the box) reads: the reader must be the
    owner or one of their active followers (`palee_profile_reader_admitted`),
    and the owner must show the thing.
    - `palee_profile_box`: the box (only while the owner is an active
      member of it) and, with `show_rank`, the current rank on its first
      ladder.
    - `palee_profile_workouts`: the latest completed workouts, title, time
      and duration only (never notes or scores), skipping any the owner
      keeps «Μόνο εγώ».
    - `palee_profile_progress`: the totals of `user_stats`.
  """

  use Ecto.Migration

  @reader "NULLIF(current_setting('app.user_id', true), '')::uuid"

  def up do
    alter table(:community_profile_cards) do
      add :box_id, references(:organizations, type: :binary_id, on_delete: :nilify_all)
      add :show_rank, :boolean, null: false, default: false
    end

    create index(:community_profile_cards, [:box_id])

    drop constraint(:community_profile_cards, :community_profile_cards_tabs_check)

    create constraint(:community_profile_cards, :community_profile_cards_tabs_check,
             check: "tabs <@ ARRAY['prs', 'badges', 'workouts', 'progress']::varchar[]"
           )

    execute("""
    CREATE FUNCTION palee_profile_reader_admitted(owner uuid)
    RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT owner = #{@reader}
        OR EXISTS (
          SELECT 1 FROM public.community_follows f
          WHERE f.user_id = #{@reader}
            AND f.target_type = 'user'
            AND f.target_id = owner
            AND f.status = 'active'
        )
    $$
    """)

    execute("""
    CREATE FUNCTION palee_profile_box(owner uuid)
    RETURNS TABLE (
      organization_id uuid,
      slug text,
      name text,
      rank_name text,
      rank_color text,
      rank_style text,
      stripes integer
    )
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT o.id, o.slug::text, o.name::text, r.name::text, r.color::text, l.style::text,
             a.stripes::integer
      FROM public.community_profile_cards c
      JOIN public.organizations o ON o.id = c.box_id AND o.status = 'active'
      LEFT JOIN LATERAL (
        SELECT award.rank_id, award.ladder_id, award.stripes
        FROM public.rank_awards award
        JOIN public.rank_ladders ladder
          ON ladder.id = award.ladder_id AND ladder.archived_at IS NULL
        WHERE c.show_rank
          AND award.organization_id = o.id
          AND award.user_id = owner
          AND award.revoked_at IS NULL
        ORDER BY ladder.position, award.awarded_on DESC, award.inserted_at DESC
        LIMIT 1
      ) a ON true
      LEFT JOIN public.ranks r ON r.id = a.rank_id
      LEFT JOIN public.rank_ladders l ON l.id = a.ladder_id
      WHERE c.user_id = owner
        AND palee_profile_reader_admitted(owner)
        AND EXISTS (
          SELECT 1 FROM public.organization_memberships m
          WHERE m.organization_id = o.id AND m.user_id = owner AND m.status = 'active'
        )
    $$
    """)

    execute("""
    CREATE FUNCTION palee_profile_workouts(owner uuid, max_rows integer)
    RETURNS TABLE (
      id uuid,
      title text,
      completed_at timestamp without time zone,
      completed_tz text,
      elapsed_ms integer
    )
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT e.id, COALESCE(s.title, w.title)::text, e.completed_at_utc::timestamp,
             e.completed_at_tz::text, e.total_elapsed_ms::integer
      FROM public.workout_executions e
      LEFT JOIN public.workout_snapshots s ON s.id = e.workout_snapshot_id
      LEFT JOIN public.master_workouts w ON w.id = e.master_workout_id
      WHERE e.user_id = owner
        AND e.status = 'completed'
        AND e.completed_at_utc IS NOT NULL
        AND e.journal_visibility <> 'private'
        AND EXISTS (
          SELECT 1 FROM public.community_profile_cards c
          WHERE c.user_id = owner AND 'workouts' = ANY (c.tabs)
        )
        AND palee_profile_reader_admitted(owner)
      ORDER BY e.completed_at_utc DESC
      LIMIT LEAST(GREATEST(max_rows, 1), 50)
    $$
    """)

    execute("""
    CREATE FUNCTION palee_profile_progress(owner uuid)
    RETURNS TABLE (
      total_workouts integer,
      current_streak integer,
      longest_streak integer,
      total_prs integer
    )
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT st.total_workouts::integer, st.current_streak::integer,
             st.longest_streak::integer, st.total_prs::integer
      FROM public.user_stats st
      WHERE st.user_id = owner
        AND EXISTS (
          SELECT 1 FROM public.community_profile_cards c
          WHERE c.user_id = owner AND 'progress' = ANY (c.tabs)
        )
        AND palee_profile_reader_admitted(owner)
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_profile_progress(uuid)")
    execute("DROP FUNCTION IF EXISTS palee_profile_workouts(uuid, integer)")
    execute("DROP FUNCTION IF EXISTS palee_profile_box(uuid)")
    execute("DROP FUNCTION IF EXISTS palee_profile_reader_admitted(uuid)")

    execute(
      "UPDATE community_profile_cards SET tabs = array(SELECT unnest(tabs) INTERSECT SELECT unnest(ARRAY['prs', 'badges']::varchar[]))"
    )

    drop constraint(:community_profile_cards, :community_profile_cards_tabs_check)

    create constraint(:community_profile_cards, :community_profile_cards_tabs_check,
             check: "tabs <@ ARRAY['prs', 'badges']::varchar[]"
           )

    alter table(:community_profile_cards) do
      remove :show_rank
      remove :box_id
    end
  end
end
