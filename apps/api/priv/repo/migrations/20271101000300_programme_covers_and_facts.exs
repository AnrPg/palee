defmodule Palee.Repo.Migrations.ProgrammeCoversAndFacts do
  @moduledoc """
  ADR-541: a programme's cover photo. `programme_cover` tenant media
  (public bucket, re-encoded in the browser and inspected like box photos);
  the programme keeps the rendered cover, the original and the edit
  (`cover_edit`), so editing again starts from the original.

  ADR-542: equipment and the time per session. `programmes.equipment` now
  holds the equipment keys the author **added** and `equipment_removed` the
  derived keys the author took away (vocabulary keys; any other value from
  before is ignored when read). Each published version keeps the facts derived from
  its frozen WODs (`facts`: equipment, minutes per session).

  `palee_marketplace_programmes` also returns the cover's object key, the
  author's equipment lists and the version's facts. It is replaced (its
  result type changes) and still pins only `search_path`.
  """

  use Ecto.Migration

  @function "palee_marketplace_programmes(text, text, text, integer, integer)"

  def up do
    alter table(:programmes) do
      add :cover_media_id, :binary_id
      add :cover_original_media_id, :binary_id
      add :cover_edit, :map
      add :equipment_removed, {:array, :string}, null: false, default: []
    end

    create constraint(:programmes, :programmes_cover_check,
             check: """
             (cover_media_id IS NOT NULL OR cover_original_media_id IS NULL)
             AND (cover_edit IS NULL OR jsonb_typeof(cover_edit) = 'object')
             AND cardinality(equipment_removed) <= 30
             """
           )

    alter table(:programme_versions) do
      add :facts, :map
    end

    rewrite_check("media_tenant_objects", "purpose", &Enum.uniq(&1 ++ ["programme_cover"]))

    execute("DROP FUNCTION IF EXISTS #{@function}")

    execute("""
    CREATE FUNCTION palee_marketplace_programmes(
      p_query text, p_goal text, p_level text, p_limit integer, p_offset integer)
    RETURNS TABLE (
      id uuid, organization_id uuid, organization_slug text, organization_name text,
      title text, summary text, level text, goal text, equipment text[],
      sessions_per_week integer, price_cents integer, currency text, weeks integer,
      version_number integer, rating_average numeric, rating_count bigint,
      published_at timestamptz, equipment_removed text[], facts jsonb,
      cover_object_key text)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
      SELECT p.id, p.organization_id, o.slug::text, o.name::text,
             p.title::text, p.summary::text, p.level::text, p.goal::text, p.equipment,
             p.sessions_per_week, p.price_cents, p.currency::text, v.weeks, v.number,
             round(avg(r.rating)::numeric, 1), count(r.id), p.published_at,
             p.equipment_removed, v.facts, m.object_key::text
      FROM programmes p
      JOIN organizations o ON o.id = p.organization_id
      JOIN programme_versions v ON v.id = p.current_version_id
      LEFT JOIN media_tenant_objects m
        ON m.id = p.cover_media_id AND m.organization_id = p.organization_id
           AND m.purpose = 'programme_cover' AND m.status = 'ready'
      LEFT JOIN programme_reviews r ON r.programme_id = p.id AND r.status = 'published'
      WHERE p.status = 'published' AND p.listing = 'marketplace' AND p.price_cents > 0
        AND o.status = 'active' AND o.activation = 'active'
        AND (p_goal IS NULL OR p.goal = p_goal)
        AND (p_level IS NULL OR p.level = p_level)
        AND (p_query IS NULL OR p.title ILIKE '%' || p_query || '%'
             OR p.summary ILIKE '%' || p_query || '%')
      GROUP BY p.id, o.slug, o.name, v.weeks, v.number, v.facts, m.object_key
      ORDER BY p.published_at DESC, p.id
      LIMIT LEAST(GREATEST(p_limit, 1), 50) OFFSET GREATEST(p_offset, 0)
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS #{@function}")

    execute("""
    CREATE FUNCTION palee_marketplace_programmes(
      p_query text, p_goal text, p_level text, p_limit integer, p_offset integer)
    RETURNS TABLE (
      id uuid, organization_id uuid, organization_slug text, organization_name text,
      title text, summary text, level text, goal text, equipment text[],
      sessions_per_week integer, price_cents integer, currency text, weeks integer,
      version_number integer, rating_average numeric, rating_count bigint,
      published_at timestamptz)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
      SELECT p.id, p.organization_id, o.slug::text, o.name::text,
             p.title::text, p.summary::text, p.level::text, p.goal::text, p.equipment,
             p.sessions_per_week, p.price_cents, p.currency::text, v.weeks, v.number,
             round(avg(r.rating)::numeric, 1), count(r.id), p.published_at
      FROM programmes p
      JOIN organizations o ON o.id = p.organization_id
      JOIN programme_versions v ON v.id = p.current_version_id
      LEFT JOIN programme_reviews r ON r.programme_id = p.id AND r.status = 'published'
      WHERE p.status = 'published' AND p.listing = 'marketplace' AND p.price_cents > 0
        AND o.status = 'active' AND o.activation = 'active'
        AND (p_goal IS NULL OR p.goal = p_goal)
        AND (p_level IS NULL OR p.level = p_level)
        AND (p_query IS NULL OR p.title ILIKE '%' || p_query || '%'
             OR p.summary ILIKE '%' || p_query || '%')
      GROUP BY p.id, o.slug, o.name, v.weeks, v.number
      ORDER BY p.published_at DESC, p.id
      LIMIT LEAST(GREATEST(p_limit, 1), 50) OFFSET GREATEST(p_offset, 0)
    $$
    """)

    execute("DELETE FROM media_tenant_objects WHERE purpose = 'programme_cover'")
    rewrite_check("media_tenant_objects", "purpose", &(&1 -- ["programme_cover"]))

    alter table(:programme_versions) do
      remove :facts
    end

    drop constraint(:programmes, :programmes_cover_check)

    alter table(:programmes) do
      remove :cover_media_id
      remove :cover_original_media_id
      remove :cover_edit
      remove :equipment_removed
    end
  end

  # Other branches add purposes too: the new list is the constraint as it
  # stands now, changed.
  defp rewrite_check(table, column, change) do
    flush()
    name = "#{table}_#{column}_check"

    %{rows: [[definition]]} =
      repo().query!(
        "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = $1 AND conrelid = to_regclass($2::text)",
        [name, table]
      )

    current = ~r/'([a-z0-9_]+)'/ |> Regex.scan(definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE #{table} DROP CONSTRAINT #{name}")

    execute(
      "ALTER TABLE #{table} ADD CONSTRAINT #{name} CHECK (#{column} IN (#{Enum.map_join(change.(current), ", ", &"'#{&1}'")}))"
    )
  end
end
