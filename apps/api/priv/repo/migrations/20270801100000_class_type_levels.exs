defmodule Palee.Repo.Migrations.ClassTypeLevels do
  @moduledoc """
  ADR-490: a class type suits one or more levels («Επίπεδο» is a multi-select).

  `class_types.levels text[]` holds a subset of `beginner intermediate advanced`
  in that order; an empty list means «Όλα τα επίπεδα». The single `level` column
  is backfilled from and then left unused, so API pods of the previous release
  keep working during the rollout. Until a later migration drops the column
  (TD-490), a trigger keeps the two in step whichever release writes:

  * a write that changes only `level` (an old pod) sets `levels` from it
    (`all_levels` → `{}`, otherwise `{level}`);
  * any other write (a new pod) sets `level` from `levels`: the one level when
    it is `beginner` or `advanced`, otherwise `all_levels`, the closest the old
    single value can say.

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
    CREATE FUNCTION palee_class_types_sync_levels() RETURNS trigger
    LANGUAGE plpgsql SET search_path = public, pg_temp
    AS $$
    BEGIN
      IF (TG_OP = 'INSERT' AND NEW.levels = '{}'::text[] AND NEW.level <> 'all_levels')
         OR (TG_OP = 'UPDATE' AND NEW.level IS DISTINCT FROM OLD.level
             AND NEW.levels IS NOT DISTINCT FROM OLD.levels) THEN
        NEW.levels := CASE WHEN NEW.level = 'all_levels' THEN '{}'::text[]
                           ELSE ARRAY[NEW.level]::text[] END;
      ELSE
        NEW.level := CASE WHEN cardinality(NEW.levels) = 1 AND NEW.levels[1] <> 'intermediate'
                          THEN NEW.levels[1] ELSE 'all_levels' END;
      END IF;
      RETURN NEW;
    END
    $$
    """)

    execute("""
    CREATE TRIGGER class_types_sync_levels
    BEFORE INSERT OR UPDATE OF level, levels ON class_types
    FOR EACH ROW EXECUTE FUNCTION palee_class_types_sync_levels()
    """)

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
    execute("DROP TRIGGER IF EXISTS class_types_sync_levels ON class_types")
    execute("DROP FUNCTION IF EXISTS palee_class_types_sync_levels()")

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
