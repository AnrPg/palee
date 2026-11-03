defmodule Palee.Repo.Migrations.FinanceDebtorContacts do
  @moduledoc """
  ADR-450: a profile deleted while it still owes a box money.

  A profile in a box's accounts is anonymised, not deleted (ADR-211), and the
  debt stays owed (ADR-220). Without a name or an address the box could no
  longer reach the person to settle it, so the box keeps the least it needs
  to claim it (GDPR art. 17(3)(e)), and only until the debt is settled:

    * `finance_debtor_contacts` (per box and person, tenant RLS): the name,
      email and box SMS number the profile had when it was deleted. Written once by the
      account-deletion sweep, read by the box's staff, deleted as soon as
      the person owes the box nothing.
    * `palee_deleting_profile_memberships(p_user_id)`: the boxes and
      memberships of a profile whose deletion is scheduled, for the sweep,
      which runs without a session scope. A narrow SECURITY DEFINER function
      (ADR-131 §2) that pins only `search_path` and answers nothing for any
      other profile.
  """

  use Ecto.Migration

  def up do
    create table(:finance_debtor_contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :display_name, :text, null: false
      add :email, :text
      add :phone_e164, :string, size: 16
      add :locale, :string, size: 10, null: false, default: "en"
      add :kept_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:finance_debtor_contacts, [:organization_id, :membership_id])
    create index(:finance_debtor_contacts, [:organization_id, :user_id])

    tenant = "organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid"

    execute("""
    CREATE POLICY finance_debtor_contacts_tenant_policy ON finance_debtor_contacts
    FOR ALL USING (#{tenant}) WITH CHECK (#{tenant})
    """)

    execute("ALTER TABLE finance_debtor_contacts ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE finance_debtor_contacts FORCE ROW LEVEL SECURITY")

    execute("""
    CREATE FUNCTION palee_deleting_profile_memberships(p_user_id uuid)
    RETURNS TABLE (organization_id uuid, membership_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT m.organization_id, m.id
      FROM memberships m
      WHERE m.user_id = p_user_id
        AND EXISTS (
          SELECT 1
          FROM account_deletions d
          JOIN users u ON u.login_id = d.login_id
          WHERE u.id = p_user_id
            AND d.status = 'scheduled'
            AND (d.scope = 'login' OR d.user_id = p_user_id)
        )
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_deleting_profile_memberships(uuid)")
    drop table(:finance_debtor_contacts)
  end
end
