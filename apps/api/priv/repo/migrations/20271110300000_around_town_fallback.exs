defmodule Palee.Repo.Migrations.AroundTownFallback do
  @moduledoc """
  Γύρω μου, «same town» fallback (ADR-583): when nothing is found near the
  origin, not even at the widest radius, boxes and open clubs whose
  location's town (`facility_locations.city`, as typed) is the origin's
  town are listed, pinned or not. A location without a map pin has no
  distance; it comes after the pinned ones.

  * `palee_town_key(text)`: a town name folded for comparison (case,
    accents, spaces and the final sigma ignored), so «ΒΟΛΟΣ», «Βόλος» and
    «βολος» are one town. The expression index makes the lookup cheap.
  * `palee_around_town_hosts`: one location per live, active gym in those
    towns (the pinned one nearest the origin first).
  * `palee_around_town_boxes` / `palee_around_town_clubs`: the same rows
    and filters as `palee_around_boxes` / `palee_around_clubs`
    (`20261218100000_around_level`), first page only (no cursor).
  """

  use Ecto.Migration

  @definer "LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp"
  @tags "p_disciplines text[], p_audiences text[], p_languages text[], p_amenities text[], p_levels text[]"

  def up do
    execute("""
    CREATE FUNCTION palee_town_key(value text)
    RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
      SELECT translate(public.palee_fold_name(value), 'ς', 'σ')
    $$
    """)

    execute("""
    CREATE INDEX facility_locations_town_key_index
      ON facility_locations (palee_town_key(city))
      WHERE archived_at IS NULL AND city IS NOT NULL
    """)

    execute("""
    CREATE FUNCTION palee_around_town_hosts(p_origin geography, p_towns text[])
    RETURNS TABLE (
      organization_id uuid, location_id uuid, latitude double precision,
      longitude double precision, neighbourhood text, city text, distance_m double precision
    )
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
      SELECT DISTINCT ON (l.organization_id)
             l.organization_id, l.id, l.latitude, l.longitude, l.neighbourhood::text, l.city::text,
             CASE WHEN l.latitude IS NOT NULL AND l.longitude IS NOT NULL
                  THEN ST_Distance(public.palee_geo_point(l.latitude, l.longitude), p_origin) END
      FROM public.facility_locations l
      JOIN public.organizations o
        ON o.id = l.organization_id AND o.status = 'active' AND o.activation = 'active'
      WHERE l.archived_at IS NULL AND l.city IS NOT NULL
        AND public.palee_town_key(l.city) = ANY (
              SELECT public.palee_town_key(t) FROM unnest(p_towns) AS t
              WHERE public.palee_town_key(t) <> '')
      ORDER BY l.organization_id, 7 NULLS LAST, l.id
    $$
    """)

    execute("""
    CREATE FUNCTION palee_around_town_boxes(
      p_origin geography, p_towns text[], p_trial_only boolean, p_exclude_ids uuid[],
      #{@tags}, p_lim integer
    )
    RETURNS TABLE (
      organization_id uuid, location_id uuid, latitude double precision,
      longitude double precision, distance_m double precision, neighbourhood text, city text,
      takes_trials boolean, snapshot jsonb, slug text, title text, logo_url text,
      primary_color text, rank integer, total bigint
    )
    #{@definer}
    AS $$
      SELECT m.organization_id, m.location_id, m.latitude, m.longitude, m.distance_m,
             m.neighbourhood, m.city, m.takes_trials, m.snapshot, m.slug, m.title, m.logo_url,
             m.primary_color, m.rank, m.total
      FROM (
        SELECT x.*, CASE WHEN x.takes_trials THEN 0 ELSE 1 END AS rank,
               count(*) OVER () AS total
        FROM (
          SELECT h.organization_id, h.location_id, h.latitude, h.longitude, h.distance_m,
                 h.neighbourhood, h.city, COALESCE(t.enabled, false) AS takes_trials,
                 pr.published_snapshot AS snapshot, o.slug::text AS slug,
                 COALESCE(NULLIF(btrim(s.brand_name), ''), o.name)::text AS title,
                 s.brand_logo_url::text AS logo_url, s.brand_primary_color::text AS primary_color
          FROM public.palee_around_town_hosts(p_origin, p_towns) h
          JOIN public.organizations o ON o.id = h.organization_id
          JOIN public.organization_public_profiles pr
            ON pr.organization_id = h.organization_id AND pr.published_at IS NOT NULL
          LEFT JOIN public.organization_settings s ON s.organization_id = h.organization_id
          LEFT JOIN public.scheduling_trial_policies t ON t.organization_id = h.organization_id
          WHERE (NOT p_trial_only OR COALESCE(t.enabled, false))
            AND (p_exclude_ids IS NULL OR NOT (h.organization_id = ANY (p_exclude_ids)))
            AND palee_around_tags_match(pr.published_snapshot, p_disciplines, p_audiences, p_languages, p_amenities)
            AND palee_around_level_match(h.organization_id, p_levels)
        ) x
      ) m
      ORDER BY m.rank, m.distance_m NULLS LAST, m.title, m.organization_id
      LIMIT p_lim
    $$
    """)

    execute("""
    CREATE FUNCTION palee_around_town_clubs(
      p_origin geography, p_towns text[], #{@tags}, p_lim integer
    )
    RETURNS TABLE (
      id uuid, organization_id uuid, latitude double precision, longitude double precision,
      distance_m double precision, total bigint
    )
    #{@definer}
    AS $$
      SELECT m.id, m.organization_id, m.latitude, m.longitude, m.distance_m, m.total
      FROM (
        SELECT c.id, c.organization_id, h.latitude, h.longitude, h.distance_m, c.name,
               count(*) OVER () AS total
        FROM public.palee_around_town_hosts(p_origin, p_towns) h
        JOIN public.community_clubs c
          ON c.organization_id = h.organization_id AND c.kind = 'open' AND c.archived_at IS NULL
        LEFT JOIN public.organization_public_profiles pr
          ON pr.organization_id = h.organization_id AND pr.published_at IS NOT NULL
        WHERE c.join_policy IN ('open', 'approval')
          AND palee_around_tags_match(pr.published_snapshot, p_disciplines, p_audiences, p_languages, p_amenities)
          AND palee_around_level_match(h.organization_id, p_levels)
      ) m
      ORDER BY m.distance_m NULLS LAST, m.name, m.id
      LIMIT p_lim
    $$
    """)
  end

  def down do
    execute(
      "DROP FUNCTION IF EXISTS palee_around_town_clubs(geography, text[], text[], text[], text[], text[], text[], integer)"
    )

    execute(
      "DROP FUNCTION IF EXISTS palee_around_town_boxes(geography, text[], boolean, uuid[], text[], text[], text[], text[], text[], integer)"
    )

    execute("DROP FUNCTION IF EXISTS palee_around_town_hosts(geography, text[])")
    execute("DROP INDEX IF EXISTS facility_locations_town_key_index")
    execute("DROP FUNCTION IF EXISTS palee_town_key(text)")
  end
end
