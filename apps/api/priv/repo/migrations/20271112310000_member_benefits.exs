defmodule Palee.Repo.Migrations.MemberBenefits do
  @moduledoc """
  ADR-612: what the box gives a member for free («Δώρο ή χάρη»), kept as a
  ledger nobody can change.

    * `finance_member_benefits`: one row per grant and one per revocation
      (`action`), with who did it (`actor_id`, `actor_roles`), when, why
      (`reason`), the request it came from (`request_id`) and what it
      touched (`details`: the usage entry, subscription, invoices and credit
      entries). Rows are insert-only: an UPDATE raises. They go only with
      their membership or organization, or with the tenant purge.
    * `finance_credit_ledger_entries.source_type` admits `forgiveness`: the
      non-cash credit that settles a forgiven debt, so reports tell it from
      a manual credit.

  The trigger function pins only `search_path` (never an extension GUC).
  """

  use Ecto.Migration

  @kinds ~w(grace free_access extra_uses package debt_forgiven)
  @sources ~w(referral_reward manual_credit promo_credit payment_application reversal invoice_offset)

  def up do
    create table(:finance_member_benefits, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      # The member and the staff member as they were: no foreign key, so the
      # lineage survives an account being deleted.
      add :user_id, :binary_id, null: false
      add :action, :string, null: false
      add :kind, :string, null: false

      add :benefit_id,
          references(:finance_member_benefits, type: :binary_id, on_delete: :delete_all)

      add :starts_on, :date
      add :ends_on, :date
      add :amount_cents, :integer
      add :details, :map, null: false, default: %{}
      add :reason, :text
      add :actor_id, :binary_id, null: false
      add :actor_roles, {:array, :string}, null: false, default: []
      add :request_id, :string
      add :idempotency_key, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:finance_member_benefits, :finance_member_benefits_action_check,
             check: "action IN ('grant', 'revoke')"
           )

    create constraint(:finance_member_benefits, :finance_member_benefits_kind_check,
             check: "kind IN (#{quoted(@kinds)})"
           )

    create constraint(:finance_member_benefits, :finance_member_benefits_revoke_check,
             check: "(action = 'revoke') = (benefit_id IS NOT NULL)"
           )

    # ANR 2026-11-10: a grace or free access always has its last day.
    create constraint(:finance_member_benefits, :finance_member_benefits_access_dates_check,
             check:
               "action = 'revoke' OR kind NOT IN ('grace', 'free_access') OR (starts_on IS NOT NULL AND ends_on IS NOT NULL AND ends_on >= starts_on)"
           )

    create constraint(:finance_member_benefits, :finance_member_benefits_reason_check,
             check: "reason IS NULL OR char_length(reason) <= 500"
           )

    create constraint(:finance_member_benefits, :finance_member_benefits_amount_check,
             check: "amount_cents IS NULL OR amount_cents >= 0"
           )

    create unique_index(:finance_member_benefits, [:organization_id, :idempotency_key])

    create unique_index(:finance_member_benefits, [:benefit_id],
             name: :finance_member_benefits_one_revocation_index,
             where: "action = 'revoke'"
           )

    create index(:finance_member_benefits, [:organization_id, :membership_id, :inserted_at])

    create index(:finance_member_benefits, [:membership_id, :ends_on],
             name: :finance_member_benefits_access_index,
             where: "action = 'grant' AND kind IN ('grace', 'free_access')"
           )

    execute("""
    CREATE OR REPLACE FUNCTION palee_member_benefits_insert_only() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'finance_member_benefits is insert-only (ADR-612)'
        USING ERRCODE = 'insufficient_privilege';
    END;
    $$ LANGUAGE plpgsql SET search_path = pg_catalog, public
    """)

    execute("""
    CREATE TRIGGER finance_member_benefits_insert_only
    BEFORE UPDATE ON finance_member_benefits
    FOR EACH ROW EXECUTE FUNCTION palee_member_benefits_insert_only()
    """)

    execute("""
    CREATE TRIGGER finance_member_benefits_apply_tenant_context
    BEFORE INSERT ON finance_member_benefits
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY finance_member_benefits_tenant_policy ON finance_member_benefits
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE finance_member_benefits ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE finance_member_benefits FORCE ROW LEVEL SECURITY")

    credit_sources(@sources ++ ["forgiveness"])
  end

  def down do
    execute(
      "DELETE FROM finance_credit_ledger_entries WHERE source_type = 'forgiveness' AND entry_type = 'grant'"
    )

    credit_sources(@sources)
    drop table(:finance_member_benefits)
    execute("DROP FUNCTION IF EXISTS palee_member_benefits_insert_only()")
  end

  defp credit_sources(sources) do
    execute(
      "ALTER TABLE finance_credit_ledger_entries DROP CONSTRAINT finance_credit_entries_source_type_check"
    )

    execute(
      "ALTER TABLE finance_credit_ledger_entries ADD CONSTRAINT finance_credit_entries_source_type_check CHECK (source_type IN (#{quoted(sources)}))"
    )
  end

  defp quoted(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
