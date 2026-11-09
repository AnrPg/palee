defmodule Palee.Repo.Migrations.FollowSuggestions do
  @moduledoc """
  ADR-561: «Ίσως γνωρίζεις», people to follow.

  * `community_follow_suggestion_dismissals`: a person's ✕ on one suggested
    person. Personal rows: only the person reads and writes their own. A
    dismissed person comes back only if they start following the viewer
    after the ✕.
  * `community_follow_suggestion_events`: anonymous daily counters per
    shown reason and event (`shown`, `followed`, `dismissed`), no person ids.
    Written only through `palee_follow_suggestion_count(reason, event, n)`;
    read through `palee_follow_suggestion_rates(since)` so the engine can
    learn which reasons lead to follows.
  * `palee_follow_suggestion_viewer()`: how much the session's account has
    to go on (follows, Buddies, open clubs, boxes, home area, disciplines),
    which moves the engine from broad to personal suggestions.
  * `palee_follow_suggestion_candidates(seed, pool, since)`: the candidate
    people and their facts, gathered from bounded sources (follows me, my
    boxes, people my follows follow, my open clubs, my home area, my
    disciplines, the seed person's follows, the most followed, the recently
    active). Never: me, people I follow or asked to follow, blocks either
    way, demo people, people who left search, my dismissals, and private
    people without a real relation (follows me, shared box or open club,
    a common follow). Box facts are dropped for people hidden from box
    member lists. Box and club names are only ever names of the viewer's
    own boxes and clubs.

  Every function is bound to `app.user_id` and pins only `search_path`
  (never an extension GUC: 42501 in prod, see 20261221100000).
  """

  use Ecto.Migration

  @me "NULLIF(current_setting('app.user_id', true), '')::uuid"
  @reasons ~w(follows_you mutual box coach club sport nearby popular newcomer via_person for_you)
  @events ~w(shown followed dismissed)

  def up do
    create table(:community_follow_suggestion_dismissals, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :target_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :dismissed_at, :utc_datetime_usec, null: false
    end

    create index(:community_follow_suggestion_dismissals, [:target_id])

    # «Κρύψε τις προτάσεις» on the Αρχική card; back on from Ρυθμίσεις.
    alter table(:community_social_settings) do
      add :show_follow_suggestions, :boolean, null: false, default: true
    end

    execute("""
    CREATE POLICY community_follow_suggestion_dismissals_owner_policy
      ON community_follow_suggestion_dismissals
      FOR ALL USING (user_id = #{@me}) WITH CHECK (user_id = #{@me})
    """)

    execute("ALTER TABLE community_follow_suggestion_dismissals ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE community_follow_suggestion_dismissals FORCE ROW LEVEL SECURITY")

    create table(:community_follow_suggestion_events, primary_key: false) do
      add :day, :date, primary_key: true
      add :reason, :text, primary_key: true
      add :event, :text, primary_key: true
      add :count, :bigint, null: false, default: 0
    end

    create constraint(:community_follow_suggestion_events, :follow_suggestion_events_reason_check,
             check: "reason IN (#{quoted(@reasons)})"
           )

    create constraint(:community_follow_suggestion_events, :follow_suggestion_events_event_check,
             check: "event IN (#{quoted(@events)})"
           )

    create constraint(:community_follow_suggestion_events, :follow_suggestion_events_count_check,
             check: "count >= 0"
           )

    # Vendors and system sessions read the raw rows; nobody writes but the
    # counting function below.
    execute("""
    CREATE POLICY community_follow_suggestion_events_read_policy
      ON community_follow_suggestion_events
      FOR SELECT USING (#{@me} IS NULL OR palee_acting_user_is_vendor())
    """)

    execute("ALTER TABLE community_follow_suggestion_events ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE community_follow_suggestion_events FORCE ROW LEVEL SECURITY")

    # The disciplines overlap source walks this.
    execute("""
    CREATE INDEX IF NOT EXISTS account_interests_disciplines_gin_index
      ON account_interests USING gin (disciplines)
    """)

    # «Who do the people I follow follow» and «who follows me» walk this.
    create_if_not_exists index(:community_follows, [:user_id, :target_type, :status])

    execute("""
    CREATE FUNCTION palee_follow_suggestion_count(p_reason text, p_event text, p_n integer)
    RETURNS void
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    BEGIN
      IF #{@me} IS NULL THEN
        RETURN;
      END IF;

      IF p_reason IS NULL OR p_reason NOT IN (#{quoted(@reasons)})
         OR p_event IS NULL OR p_event NOT IN (#{quoted(@events)})
         OR p_n IS NULL OR p_n < 1 OR p_n > 100 THEN
        RAISE EXCEPTION 'invalid follow suggestion count % % %', p_reason, p_event, p_n
          USING ERRCODE = 'invalid_parameter_value';
      END IF;

      INSERT INTO public.community_follow_suggestion_events AS e (day, reason, event, count)
      VALUES ((now() AT TIME ZONE 'UTC')::date, p_reason, p_event, p_n)
      ON CONFLICT (day, reason, event) DO UPDATE SET count = e.count + EXCLUDED.count;
    END
    $$
    """)

    execute("""
    CREATE FUNCTION palee_follow_suggestion_rates(p_since date)
    RETURNS TABLE (reason text, event text, count bigint)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT e.reason, e.event, sum(e.count)::bigint
      FROM public.community_follow_suggestion_events e
      WHERE #{@me} IS NOT NULL AND e.day >= p_since
      GROUP BY e.reason, e.event
    $$
    """)

    execute("""
    CREATE FUNCTION palee_follow_suggestion_viewer()
    RETURNS TABLE (following integer, buddies integer, clubs integer, boxes integer,
                   has_area boolean, disciplines integer)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      WITH me AS (SELECT #{@me} AS id)
      SELECT
        (SELECT count(*) FROM public.community_follows f
          WHERE f.user_id = me.id AND f.target_type = 'user' AND f.status = 'active')::int,
        (SELECT count(*) FROM public.community_follows f
          JOIN public.community_follows b ON b.user_id = f.target_id AND b.target_id = f.user_id
            AND b.target_type = 'user' AND b.status = 'active'
          WHERE f.user_id = me.id AND f.target_type = 'user' AND f.status = 'active')::int,
        (SELECT count(*) FROM public.community_club_memberships m
          JOIN public.community_clubs c ON c.id = m.club_id
          WHERE m.user_id = me.id AND m.status = 'active' AND c.kind = 'open'
            AND c.archived_at IS NULL)::int,
        (SELECT count(*) FROM public.organization_memberships om
          JOIN public.organizations o ON o.id = om.organization_id
          WHERE om.user_id = me.id AND om.status = 'active' AND o.status = 'active'
            AND o.activation = 'active'
            AND NOT (om.roles <@ ARRAY['guest']::varchar[]))::int,
        EXISTS (SELECT 1 FROM public.user_home_areas a WHERE a.user_id = me.id),
        COALESCE((SELECT cardinality(i.disciplines) FROM public.account_interests i
          WHERE i.user_id = me.id), 0)
      FROM me
      WHERE me.id IS NOT NULL
    $$
    """)

    execute(candidates_function())
  end

  def down do
    execute(
      "DROP FUNCTION IF EXISTS palee_follow_suggestion_candidates(uuid, integer, timestamptz)"
    )

    execute("DROP FUNCTION IF EXISTS palee_follow_suggestion_viewer()")
    execute("DROP FUNCTION IF EXISTS palee_follow_suggestion_rates(date)")
    execute("DROP FUNCTION IF EXISTS palee_follow_suggestion_count(text, text, integer)")
    drop_if_exists index(:community_follows, [:user_id, :target_type, :status])
    execute("DROP INDEX IF EXISTS account_interests_disciplines_gin_index")
    drop table(:community_follow_suggestion_events)
    drop table(:community_follow_suggestion_dismissals)

    alter table(:community_social_settings) do
      remove :show_follow_suggestions
    end
  end

  defp quoted(values), do: Enum.map_join(values, ", ", &"'#{&1}'")

  defp candidates_function do
    """
    CREATE FUNCTION palee_follow_suggestion_candidates(
      p_seed uuid, p_pool integer, p_recent_since timestamptz)
    RETURNS TABLE (
      user_id uuid, follows_me boolean, box_id uuid, box_name text, box_coach boolean,
      mutual_count integer, mutual_ids uuid[], club_id uuid, club_name text,
      shared_disciplines text[], nearby boolean, via_seed boolean, followers integer,
      active_days integer, newcomer boolean, private boolean)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $fn$
      WITH me AS (SELECT #{@me} AS id),
      pool AS (SELECT LEAST(GREATEST(COALESCE(p_pool, 1), 1), 500) AS n),
      my_follows AS (
        SELECT f.target_id AS id FROM community_follows f
        WHERE f.user_id = (SELECT id FROM me) AND f.target_type = 'user' AND f.status = 'active'
      ),
      my_orgs AS (
        SELECT om.organization_id AS id, o.name
        FROM organization_memberships om
        JOIN organizations o ON o.id = om.organization_id
        WHERE om.user_id = (SELECT id FROM me) AND om.status = 'active'
          AND o.status = 'active' AND o.activation = 'active'
          AND NOT (om.roles <@ ARRAY['guest']::varchar[])
      ),
      my_clubs AS (
        SELECT c.id, c.name FROM community_club_memberships m
        JOIN community_clubs c ON c.id = m.club_id
        WHERE m.user_id = (SELECT id FROM me) AND m.status = 'active'
          AND c.kind = 'open' AND c.archived_at IS NULL
      ),
      my_areas AS (
        SELECT a.neighbourhood_id AS id FROM user_home_areas a
        WHERE a.user_id = (SELECT id FROM me)
      ),
      my_disciplines AS (
        SELECT COALESCE((SELECT i.disciplines FROM account_interests i
          WHERE i.user_id = (SELECT id FROM me)), ARRAY[]::varchar[]) AS d
      ),
      -- The seed person's follows count only when the viewer may see them:
      -- the seed is public or the viewer follows them.
      seed AS (
        SELECT p_seed AS id
        WHERE p_seed IS NOT NULL
          AND (p_seed IN (SELECT id FROM my_follows)
            OR NOT COALESCE((SELECT s.private_account FROM community_social_settings s
              WHERE s.user_id = p_seed), false))
      ),
      src AS (
        (SELECT f.user_id AS id FROM community_follows f
          WHERE f.target_type = 'user' AND f.target_id = (SELECT id FROM me) AND f.status = 'active'
          ORDER BY f.inserted_at DESC LIMIT (SELECT n FROM pool))
        UNION
        (SELECT om.user_id FROM organization_memberships om
          WHERE om.organization_id IN (SELECT id FROM my_orgs) AND om.status = 'active'
            AND NOT (om.roles <@ ARRAY['guest']::varchar[])
          ORDER BY om.joined_at DESC NULLS LAST, om.user_id LIMIT (SELECT n FROM pool))
        UNION
        (SELECT f.target_id FROM community_follows f
          WHERE f.user_id IN (SELECT id FROM my_follows) AND f.target_type = 'user'
            AND f.status = 'active'
          GROUP BY f.target_id ORDER BY count(*) DESC, f.target_id LIMIT (SELECT n FROM pool))
        UNION
        (SELECT m.user_id FROM community_club_memberships m
          WHERE m.club_id IN (SELECT id FROM my_clubs) AND m.status = 'active'
          ORDER BY m.inserted_at DESC, m.user_id LIMIT (SELECT n FROM pool))
        UNION
        (SELECT a.user_id FROM user_home_areas a
          WHERE a.neighbourhood_id IN (SELECT id FROM my_areas)
          ORDER BY a.updated_at DESC, a.user_id LIMIT (SELECT n FROM pool))
        UNION
        (SELECT i.user_id FROM account_interests i
          WHERE i.disciplines && (SELECT d FROM my_disciplines)
          ORDER BY i.updated_at DESC, i.user_id LIMIT (SELECT n FROM pool))
        UNION
        (SELECT f.target_id FROM community_follows f
          WHERE f.user_id = (SELECT id FROM seed) AND f.target_type = 'user' AND f.status = 'active'
          ORDER BY f.inserted_at DESC LIMIT (SELECT n FROM pool))
        UNION
        (SELECT f.target_id FROM community_follows f
          WHERE f.target_type = 'user' AND f.status = 'active'
          GROUP BY f.target_id ORDER BY count(*) DESC, f.target_id LIMIT (SELECT n FROM pool))
        UNION
        (SELECT p.user_id FROM community_profile_posts p
          WHERE p.audience = 'public' AND p.deleted_at IS NULL AND p.inserted_at >= p_recent_since
          GROUP BY p.user_id ORDER BY max(p.inserted_at) DESC, p.user_id LIMIT (SELECT n FROM pool))
      ),
      cands AS (
        SELECT u.id, u.inserted_at,
          COALESCE(s.private_account, false) AS private,
          COALESCE(s.hide_from_members, false) AS hidden_member
        FROM users u
        LEFT JOIN community_social_settings s ON s.user_id = u.id
        WHERE (SELECT id FROM me) IS NOT NULL
          AND u.id IN (SELECT id FROM src)
          AND u.id <> (SELECT id FROM me)
          AND u.demo_organization_id IS NULL
          AND COALESCE(s.searchable, true)
          AND NOT EXISTS (
            SELECT 1 FROM community_follows f
            WHERE f.user_id = (SELECT id FROM me) AND f.target_type = 'user' AND f.target_id = u.id)
          AND NOT EXISTS (
            SELECT 1 FROM community_user_blocks b
            WHERE (b.user_id = (SELECT id FROM me) AND b.blocked_user_id = u.id)
               OR (b.user_id = u.id AND b.blocked_user_id = (SELECT id FROM me)))
          AND NOT EXISTS (
            SELECT 1 FROM community_follow_suggestion_dismissals d
            WHERE d.user_id = (SELECT id FROM me) AND d.target_id = u.id
              AND NOT EXISTS (
                SELECT 1 FROM community_follows f
                WHERE f.user_id = u.id AND f.target_type = 'user'
                  AND f.target_id = (SELECT id FROM me) AND f.status = 'active'
                  AND f.inserted_at > d.dismissed_at))
      ),
      facts AS (
        SELECT c.id, c.private,
          EXISTS (
            SELECT 1 FROM community_follows f
            WHERE f.user_id = c.id AND f.target_type = 'user'
              AND f.target_id = (SELECT id FROM me) AND f.status = 'active') AS follows_me,
          box.id AS box_id, box.name AS box_name,
          COALESCE(box.coach, false) AS box_coach,
          COALESCE(box.joined_recently, false) AS joined_box_recently,
          (SELECT count(*) FROM community_follows f
            WHERE f.target_id = c.id AND f.target_type = 'user' AND f.status = 'active'
              AND f.user_id IN (SELECT id FROM my_follows))::int AS mutual_count,
          ARRAY(
            SELECT f.user_id FROM community_follows f
            WHERE f.target_id = c.id AND f.target_type = 'user' AND f.status = 'active'
              AND f.user_id IN (SELECT id FROM my_follows)
            ORDER BY f.inserted_at, f.user_id LIMIT 2) AS mutual_ids,
          club.id AS club_id, club.name AS club_name,
          ARRAY(
            SELECT x FROM unnest(COALESCE((SELECT i.disciplines FROM account_interests i
              WHERE i.user_id = c.id), ARRAY[]::varchar[])) AS x
            WHERE ARRAY[x] <@ (SELECT d FROM my_disciplines)
            ORDER BY x)::text[] AS shared_disciplines,
          EXISTS (
            SELECT 1 FROM user_home_areas a
            WHERE a.user_id = c.id AND a.neighbourhood_id IN (SELECT id FROM my_areas)) AS nearby,
          EXISTS (
            SELECT 1 FROM community_follows f
            WHERE f.user_id = (SELECT id FROM seed) AND f.target_type = 'user'
              AND f.target_id = c.id AND f.status = 'active') AS via_seed,
          (SELECT count(*) FROM community_follows f
            WHERE f.target_id = c.id AND f.target_type = 'user' AND f.status = 'active')::int
            AS followers,
          (SELECT count(DISTINCT day) FROM (
            SELECT (p.inserted_at AT TIME ZONE 'UTC')::date AS day FROM community_profile_posts p
              WHERE p.user_id = c.id AND p.deleted_at IS NULL AND p.inserted_at >= p_recent_since
            UNION
            SELECT (t.inserted_at AT TIME ZONE 'UTC')::date FROM training_log_entries t
              WHERE t.user_id = c.id AND t.inserted_at >= p_recent_since) days)::int AS active_days,
          c.inserted_at >= p_recent_since AS joined_palee_recently
        FROM cands c
        LEFT JOIN LATERAL (
          SELECT mo.id, mo.name,
            om.roles && ARRAY['owner', 'coach']::varchar[] AS coach,
            COALESCE(om.joined_at, om.inserted_at) >= p_recent_since AS joined_recently
          FROM organization_memberships om
          JOIN my_orgs mo ON mo.id = om.organization_id
          WHERE om.user_id = c.id AND om.status = 'active' AND NOT c.hidden_member
            AND NOT (om.roles <@ ARRAY['guest']::varchar[])
          ORDER BY (om.roles && ARRAY['owner', 'coach']::varchar[]) DESC, mo.name, mo.id
          LIMIT 1
        ) box ON true
        LEFT JOIN LATERAL (
          SELECT mc.id, mc.name FROM community_club_memberships m
          JOIN my_clubs mc ON mc.id = m.club_id
          WHERE m.user_id = c.id AND m.status = 'active'
          ORDER BY mc.name, mc.id
          LIMIT 1
        ) club ON true
      )
      SELECT f.id, f.follows_me, f.box_id, f.box_name, f.box_coach, f.mutual_count,
        f.mutual_ids, f.club_id, f.club_name, f.shared_disciplines, f.nearby, f.via_seed,
        f.followers, f.active_days,
        (f.joined_palee_recently OR f.joined_box_recently) AS newcomer,
        f.private
      FROM facts f
      WHERE NOT f.private
        OR f.follows_me OR f.box_id IS NOT NULL OR f.club_id IS NOT NULL OR f.mutual_count > 0
      ORDER BY f.id
    $fn$
    """
  end
end
