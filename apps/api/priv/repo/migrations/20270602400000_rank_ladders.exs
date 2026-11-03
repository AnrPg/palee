defmodule Palee.Repo.Migrations.RankLadders do
  @moduledoc """
  ADR-377 (CP-E2, «Βαθμοί»): belts and levels a box defines per discipline.

    * `rank_ladders` – one ladder per discipline (a workout type of ADR-275:
      «Ζώνες BJJ», «Επίπεδα ενόργανης»), optionally limited to class types
      whose attendance counts;
    * `ranks` – its ordered steps with colour, stripes, requirements and
      an optional scale level (ADR-128) the rank suggests;
    * `rank_awards` – every promotion (and stripe), with who awarded it,
      the diploma number and, when withdrawn, why. Never deleted while the
      box exists: a withdrawn award stays in the history.
  """

  use Ecto.Migration

  @tables ~w(rank_ladders ranks rank_awards)

  def up do
    create table(:rank_ladders, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, size: 60, null: false
      add :discipline, :string, size: 40, null: false
      add :style, :string, size: 16, null: false, default: "belt"
      add :class_type_ids, {:array, :binary_id}, null: false, default: []
      add :position, :integer, null: false, default: 0
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:rank_ladders, [:id, :organization_id],
             name: :rank_ladders_id_organization_index
           )

    create unique_index(:rank_ladders, [:organization_id, :name],
             where: "archived_at IS NULL",
             name: :rank_ladders_organization_name_index
           )

    create constraint(:rank_ladders, :rank_ladders_check,
             check: "style IN ('belt', 'level') AND position >= 0"
           )

    create table(:ranks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :ladder_id, :binary_id, null: false
      add :position, :integer, null: false
      add :name, :string, size: 60, null: false
      add :color, :string, size: 16
      add :max_stripes, :integer, null: false, default: 0
      add :requirements, :map, null: false, default: %{}
      add :scale_level_slug, :string, size: 60
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE ranks ADD CONSTRAINT ranks_ladder_fkey
    FOREIGN KEY (ladder_id, organization_id)
    REFERENCES rank_ladders (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:ranks, [:id, :organization_id], name: :ranks_id_organization_index)
    create unique_index(:ranks, [:ladder_id, :position])

    create constraint(:ranks, :ranks_check,
             check: "position >= 0 AND max_stripes BETWEEN 0 AND 10"
           )

    create table(:rank_awards, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :ladder_id, :binary_id, null: false
      add :rank_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :stripes, :integer, null: false, default: 0
      add :awarded_on, :date, null: false
      add :awarded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :note, :string, size: 500
      add :skills_checked, {:array, :string}, null: false, default: []
      add :certificate_number, :string, size: 32, null: false
      add :revoked_at, :utc_datetime_usec
      add :revoked_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :revoke_reason, :string, size: 280
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE rank_awards ADD CONSTRAINT rank_awards_ladder_fkey
    FOREIGN KEY (ladder_id, organization_id)
    REFERENCES rank_ladders (id, organization_id) ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE rank_awards ADD CONSTRAINT rank_awards_rank_fkey
    FOREIGN KEY (rank_id, organization_id)
    REFERENCES ranks (id, organization_id) ON DELETE RESTRICT
    """)

    create unique_index(:rank_awards, [:organization_id, :certificate_number])
    create index(:rank_awards, [:organization_id, :user_id, :ladder_id])

    create constraint(:rank_awards, :rank_awards_check,
             check:
               "stripes BETWEEN 0 AND 10 AND (revoked_at IS NULL OR revoke_reason IS NOT NULL)"
           )

    for table <- @tables do
      execute("""
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """)

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end
  end

  def down do
    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))
  end
end
