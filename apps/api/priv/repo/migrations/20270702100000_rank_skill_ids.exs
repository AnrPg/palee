defmodule Palee.Repo.Migrations.RankSkillIds do
  @moduledoc """
  ADR-400 follow-up: every skill of a rank gets a stable id
  (`ranks.requirements.skill_ids`, in the order of `skills`), and a tick
  (`rank_skill_checks.skill_id`) points at it, so renaming or reordering a
  skill in the curriculum editor keeps the ticks. Existing skills get new
  ids and existing ticks are matched to them by their text. A tick whose
  text is no longer on the rank keeps a null id and stays out of progress,
  as before.

  `notified_at` (ADR-400 follow-up): when the person was told about the
  tick in a grouped notification; ticks made before are marked as told.
  """

  use Ecto.Migration

  def up do
    alter table(:rank_skill_checks) do
      add :skill_id, :binary_id
      add :notified_at, :utc_datetime_usec
    end

    flush()

    # The backfill runs as the table owner across every box.
    execute("ALTER TABLE ranks NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE rank_skill_checks NO FORCE ROW LEVEL SECURITY")

    execute("""
    UPDATE ranks SET requirements = requirements || jsonb_build_object(
      'skill_ids',
      (SELECT jsonb_agg(gen_random_uuid()::text ORDER BY s.ord)
       FROM jsonb_array_elements(requirements->'skills') WITH ORDINALITY AS s(value, ord))
    )
    WHERE jsonb_typeof(requirements->'skills') = 'array'
      AND jsonb_array_length(requirements->'skills') > 0
      AND NOT (requirements ? 'skill_ids')
    """)

    execute("""
    UPDATE rank_skill_checks AS c SET skill_id = (ids.value #>> '{}')::uuid
    FROM ranks AS r,
      jsonb_array_elements(r.requirements->'skills') WITH ORDINALITY AS s(value, ord),
      jsonb_array_elements(r.requirements->'skill_ids') WITH ORDINALITY AS ids(value, ord)
    WHERE r.id = c.rank_id AND s.ord = ids.ord AND s.value #>> '{}' = c.skill
      AND c.skill_id IS NULL
    """)

    execute("UPDATE rank_skill_checks SET notified_at = now()")

    execute("ALTER TABLE ranks FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE rank_skill_checks FORCE ROW LEVEL SECURITY")

    drop index(:rank_skill_checks, [:organization_id, :user_id, :rank_id, :skill])
    create unique_index(:rank_skill_checks, [:organization_id, :user_id, :rank_id, :skill_id])
  end

  def down do
    drop index(:rank_skill_checks, [:organization_id, :user_id, :rank_id, :skill_id])

    execute("ALTER TABLE ranks NO FORCE ROW LEVEL SECURITY")
    execute("UPDATE ranks SET requirements = requirements - 'skill_ids'")
    execute("ALTER TABLE ranks FORCE ROW LEVEL SECURITY")

    create unique_index(:rank_skill_checks, [:organization_id, :user_id, :rank_id, :skill])

    alter table(:rank_skill_checks) do
      remove :skill_id
      remove :notified_at
    end
  end
end
