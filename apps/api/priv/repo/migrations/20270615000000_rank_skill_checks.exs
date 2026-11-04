defmodule Palee.Repo.Migrations.RankSkillChecks do
  @moduledoc """
  ADR-400: a coach ticks a person's skills of a rank one by one, between
  promotions («Δεξιότητες»). One row per person, rank and skill; unticking
  deletes it. The skill is the text of the rank's requirements when ticked,
  so renaming a skill in the ladder leaves old ticks out of the progress.
  """

  use Ecto.Migration

  def up do
    create table(:rank_skill_checks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :rank_id, :binary_id, null: false
      add :skill, :string, size: 120, null: false
      add :checked_on, :date, null: false
      add :checked_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :note, :string, size: 280
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE rank_skill_checks ADD CONSTRAINT rank_skill_checks_rank_fkey
    FOREIGN KEY (rank_id, organization_id)
    REFERENCES ranks (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:rank_skill_checks, [:organization_id, :user_id, :rank_id, :skill])

    execute("""
    CREATE TRIGGER rank_skill_checks_apply_tenant_context
    BEFORE INSERT OR UPDATE ON rank_skill_checks
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY rank_skill_checks_tenant_policy ON rank_skill_checks
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE rank_skill_checks ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE rank_skill_checks FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:rank_skill_checks)
  end
end
