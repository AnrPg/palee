defmodule Palee.Repo.Migrations.CreateRetentionRisks do
  @moduledoc """
  ADR-347: «Σε κίνδυνο». Once a day each box's members get an explainable
  risk score from their own attendance, bookings and payments at this box.
  One row per box member holds the latest score, its level, the reasons
  behind it (each with its points and the facts it read) and what staff did
  about it: «Το είδα» hides the member until a date, «Μίλησα» records the
  contact. Rows are recomputed in place; nothing is kept per day.
  """

  use Ecto.Migration

  def change do
    create table(:retention_risks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :score, :integer, null: false
      add :level, :string, null: false
      add :reasons, {:array, :map}, null: false, default: []
      add :suggested_action, :string
      add :computed_at, :utc_datetime_usec, null: false
      add :level_since, :utc_datetime_usec, null: false
      add :snoozed_until, :date
      add :contacted_at, :utc_datetime_usec
      add :contacted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :win_back_queued_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:retention_risks, [:organization_id, :user_id])
    create index(:retention_risks, [:organization_id, :level, :score])
    create index(:retention_risks, [:user_id])
    create index(:retention_risks, [:contacted_by_id])

    create constraint(:retention_risks, :retention_risks_level_check,
             check: "level IN ('low', 'medium', 'high')"
           )

    create constraint(:retention_risks, :retention_risks_score_check,
             check: "score BETWEEN 0 AND 100"
           )

    execute(
      """
      CREATE TRIGGER retention_risks_apply_tenant_context
      BEFORE INSERT OR UPDATE ON retention_risks
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """,
      "DROP TRIGGER IF EXISTS retention_risks_apply_tenant_context ON retention_risks"
    )

    execute(
      """
      CREATE POLICY retention_risks_tenant_policy ON retention_risks
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS retention_risks_tenant_policy ON retention_risks"
    )

    execute(
      "ALTER TABLE retention_risks ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE retention_risks DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE retention_risks FORCE ROW LEVEL SECURITY",
      "ALTER TABLE retention_risks NO FORCE ROW LEVEL SECURITY"
    )
  end
end
