defmodule Palee.Repo.Migrations.CreateRetentionRiskActions do
  @moduledoc """
  ADR-384: what staff did about a box member «Σε κίνδυνο», one row per
  action, with who did it and when. «Επικοινώνησα» (with the channel) and
  «Αργότερα» (with the date the member comes back to the list) are kept as
  a log; `retention_risks` keeps only the latest contact.
  """

  use Ecto.Migration

  def change do
    create table(:retention_risk_actions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :channel, :string
      add :snoozed_until, :date
      add :at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:retention_risk_actions, [:organization_id, :user_id, :at])
    create index(:retention_risk_actions, [:user_id])
    create index(:retention_risk_actions, [:actor_id])

    create constraint(:retention_risk_actions, :retention_risk_actions_kind_check,
             check: "kind IN ('contacted', 'snoozed', 'unsnoozed')"
           )

    execute(
      """
      CREATE TRIGGER retention_risk_actions_apply_tenant_context
      BEFORE INSERT OR UPDATE ON retention_risk_actions
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """,
      "DROP TRIGGER IF EXISTS retention_risk_actions_apply_tenant_context ON retention_risk_actions"
    )

    execute(
      """
      CREATE POLICY retention_risk_actions_tenant_policy ON retention_risk_actions
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS retention_risk_actions_tenant_policy ON retention_risk_actions"
    )

    execute(
      "ALTER TABLE retention_risk_actions ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE retention_risk_actions DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE retention_risk_actions FORCE ROW LEVEL SECURITY",
      "ALTER TABLE retention_risk_actions NO FORCE ROW LEVEL SECURITY"
    )
  end
end
