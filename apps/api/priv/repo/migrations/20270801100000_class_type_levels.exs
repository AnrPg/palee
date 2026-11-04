defmodule Palee.Repo.Migrations.ClassTypeLevels do
  @moduledoc """
  ADR-490: a class type suits one or more levels («Επίπεδο» is a multi-select).

  `class_types.levels text[]` holds a subset of `beginner intermediate advanced`
  in that order; an empty list means «Όλα τα επίπεδα». The single `level` column
  is backfilled from and then left unused, so API pods of the previous release
  keep working during the rollout; a later migration drops it (TD in ADR-490).

  Γύρω μου's `palee_around_level_match` now reads `levels`: a class type with no
  levels suits every level, otherwise it matches when the lists overlap. Saved
  Γύρω μου filters lose the retired `all_levels` value.
  """

  use Ecto.Migration

  def up do
    alter table(:class_types) do
      add :levels, {:array, :text}, null: false, default: []
    end

    execute("""
    UPDATE class_types SET levels = ARRAY[level]::text[]
    WHERE level IN ('beginner', 'advanced')
    """)

    create constraint(:class_types, :class_types_levels_check,
             check: "levels <@ ARRAY['beginner', 'intermediate', 'advanced']::text[]"
           )

    execute("""
    CREATE OR REPLACE FUNCTION palee_around_level_match(p_organization_id uuid, p_levels text[])
    RETURNS boolean
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
      SELECT p_levels IS NULL OR EXISTS (
        SELECT 1 FROM public.class_types ct
        WHERE ct.organization_id = p_organization_id AND ct.archived_at IS NULL
          AND (ct.levels = '{}'::text[] OR ct.levels && p_levels))
    $$
    """)

    execute("""
    UPDATE saved_filters
    SET params = jsonb_set(params, '{levels}',
          COALESCE((SELECT jsonb_agg(v) FROM jsonb_array_elements_text(params->'levels') AS v
                    WHERE v <> 'all_levels'), '[]'::jsonb))
    WHERE surface = 'around_me' AND jsonb_typeof(params->'levels') = 'array'
      AND params->'levels' ? 'all_levels'
    """)
  end

  def down do
    execute("""
    UPDATE class_types
    SET level = CASE WHEN cardinality(levels) = 1 AND levels[1] <> 'intermediate'
                     THEN levels[1] ELSE 'all_levels' END
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_around_level_match(p_organization_id uuid, p_levels text[])
    RETURNS boolean
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
      SELECT p_levels IS NULL OR EXISTS (
        SELECT 1 FROM public.class_types ct
        WHERE ct.organization_id = p_organization_id AND ct.archived_at IS NULL
          AND ct.level = ANY (p_levels))
    $$
    """)

    drop constraint(:class_types, :class_types_levels_check)

    alter table(:class_types) do
      remove :levels
    end
  end
end
