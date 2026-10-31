defmodule Palee.Repo.Migrations.CoachPay do
  @moduledoc """
  ADR-341 (CP-A6): coach pay and commissions.

    * `coach_pay_rules` – how a coach is paid: per class, per attendee, per
      personal-training session, or a percent of the sales attributed to
      them; dated, so a change of terms keeps earlier periods as they were.
    * `coach_pay_periods` – a pay period (gym-local dates), `draft` until
      approved, then `approved` and `exported` (handed to the accountant).
    * `coach_pay_statements` / `coach_pay_lines` – one statement per coach
      and period, its lines naming the class, session or payment they come
      from (revenue lineage, ADR-192), plus staff adjustments.

  Coach pay never writes Finance or issues fiscal documents: it reads the
  schedule and the money and produces a report for payroll.

  A coach's statements are pay records the box keeps (ADR-117), so a coach
  who deletes their account is anonymised in place, not deleted
  (`palee_user_has_retained_records`, ADR-211).
  """

  use Ecto.Migration

  @tables ~w(coach_pay_rules coach_pay_periods coach_pay_statements coach_pay_lines)

  def change do
    create table(:coach_pay_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :coach_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :kind, :string, null: false
      add :amount_cents, :integer
      add :percent_bps, :integer
      add :currency, :string, size: 3, null: false
      add :class_type_ids, {:array, :binary_id}, null: false, default: []
      add :count_statuses, {:array, :string}, null: false, default: ["attended"]
      add :min_attendees, :integer, null: false, default: 0
      add :max_attendees, :integer
      add :sales_scope, :string
      add :starts_on, :date, null: false
      add :ends_on, :date
      add :note, :string
      add :archived_at, :utc_datetime_usec
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:coach_pay_rules, :coach_pay_rules_kind_check,
             check: "kind IN ('per_class', 'per_attendee', 'per_session', 'percent_of_sales')"
           )

    create constraint(:coach_pay_rules, :coach_pay_rules_amount_check,
             check: """
             (kind = 'percent_of_sales' AND percent_bps BETWEEN 1 AND 10000
               AND sales_scope IN ('personal_training', 'sold_by'))
             OR (kind <> 'percent_of_sales' AND amount_cents BETWEEN 1 AND 10000000)
             """
           )

    create constraint(:coach_pay_rules, :coach_pay_rules_dates_check,
             check: "ends_on IS NULL OR ends_on >= starts_on"
           )

    create index(:coach_pay_rules, [:organization_id, :coach_user_id])

    create table(:coach_pay_periods, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :starts_on, :date, null: false
      add :ends_on, :date, null: false
      add :status, :string, null: false, default: "draft"
      add :currency, :string, size: 3, null: false
      add :total_cents, :bigint, null: false, default: 0
      add :calculated_at, :utc_datetime_usec
      add :approved_at, :utc_datetime_usec
      add :approved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :exported_at, :utc_datetime_usec
      add :reopen_reason, :string
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:coach_pay_periods, :coach_pay_periods_status_check,
             check: "status IN ('draft', 'approved', 'exported')"
           )

    create constraint(:coach_pay_periods, :coach_pay_periods_dates_check,
             check: "ends_on >= starts_on AND ends_on - starts_on <= 92"
           )

    create unique_index(:coach_pay_periods, [:organization_id, :starts_on])

    create table(:coach_pay_statements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :period_id, references(:coach_pay_periods, type: :binary_id, on_delete: :delete_all),
        null: false

      add :coach_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :total_cents, :bigint, null: false, default: 0
      add :line_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:coach_pay_statements, [:period_id, :coach_user_id])
    create index(:coach_pay_statements, [:organization_id, :coach_user_id])

    create table(:coach_pay_lines, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :statement_id,
          references(:coach_pay_statements, type: :binary_id, on_delete: :delete_all),
          null: false

      add :rule_id, references(:coach_pay_rules, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :source_type, :string, null: false
      add :source_id, :binary_id
      add :occurred_on, :date, null: false
      add :description, :string, null: false
      add :quantity, :integer, null: false, default: 1
      add :unit_cents, :integer
      add :base_cents, :integer
      add :percent_bps, :integer
      add :amount_cents, :integer, null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:coach_pay_lines, :coach_pay_lines_kind_check,
             check:
               "kind IN ('per_class', 'per_attendee', 'per_session', 'percent_of_sales', 'clawback', 'adjustment')"
           )

    create constraint(:coach_pay_lines, :coach_pay_lines_source_check,
             check:
               "source_type IN ('scheduled_class', 'appointment_slot', 'finance_payment', 'finance_reversal', 'manual')"
           )

    create index(:coach_pay_lines, [:statement_id])

    execute(retained_records(true), retained_records(false))

    for table <- @tables do
      execute(
        """
        CREATE TRIGGER #{table}_apply_tenant_context
        BEFORE INSERT OR UPDATE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
        """,
        "DROP TRIGGER IF EXISTS #{table}_apply_tenant_context ON #{table}"
      )

      execute(
        """
        CREATE POLICY #{table}_tenant_policy ON #{table}
        USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
        WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
        """,
        "DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}"
      )

      execute(
        "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY",
        "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY"
      )

      execute(
        "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY",
        "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"
      )
    end
  end

  defp retained_records(with_coach_pay?) do
    coach_pay =
      if with_coach_pay?,
        do:
          "\n    OR EXISTS (SELECT 1 FROM public.coach_pay_statements WHERE coach_user_id = p_user_id)",
        else: ""

    """
    CREATE OR REPLACE FUNCTION palee_user_has_retained_records(p_user_id uuid)
    RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (SELECT 1 FROM public.memberships WHERE user_id = p_user_id)
          OR EXISTS (SELECT 1 FROM public.finance_invoices WHERE user_id = p_user_id)
          OR EXISTS (SELECT 1 FROM public.finance_credit_ledger_entries WHERE user_id = p_user_id)
          OR EXISTS (SELECT 1 FROM public.finance_payment_reversals WHERE user_id = p_user_id)
          OR EXISTS (SELECT 1 FROM public.finance_refund_receipts WHERE user_id = p_user_id)#{coach_pay}
    $$
    """
  end
end
