defmodule Palee.Repo.Migrations.CoachPayPlus do
  @moduledoc """
  ADR-382: coach pay, additions to ADR-341 (product owner, 2026-11-01).

    * `coach_pay_rules` – kind `fixed` (an amount per month, week or day,
      prorated by the calendar days it is valid in the period) with its
      `frequency`; `percent_of_sales` also on the payments of the coach's
      own clients (`own_clients`) or of the whole box (`box_all`).
    * `coach_pay_items` – the box's catalogue of overtime (an amount per
      hour above a weekly threshold of hours, both required) and
      allowances (per period or per occurrence, added by hand), with the
      roles each applies to.
    * `amount_basis` (`gross` | `net`, default `gross`) on rules, pay
      items and lines: whether an amount is before or after the person's
      taxes and contributions (Palee computes neither). Statements and
      periods keep `gross_cents` and `net_cents` apart.
    * `coach_pay_lines` – kinds `fixed`, `overtime`, `allowance` and
      `ad_hoc` (a payment by hand with its reason), the line's `note`, the
      pay item it comes from and the `quantity_divisor` of prorated and
      hourly lines (amount = unit × quantity ÷ divisor, rounded half up).
    * `coach_pay_statements.rule_terms` – the terms of each rule as it was
      when the statement was calculated, so an approved statement keeps
      showing what it paid by.

  Statements stay pay records the box keeps 10 years (ADR-117, ADR-341);
  `palee_user_has_retained_records` already covers every statement.
  """

  use Ecto.Migration

  @kinds_before "'per_class', 'per_attendee', 'per_session', 'percent_of_sales'"
  @kinds "'per_class', 'per_attendee', 'per_session', 'percent_of_sales', 'fixed'"
  @line_kinds_before @kinds_before <> ", 'clawback', 'adjustment'"
  @line_kinds @kinds <> ", 'clawback', 'adjustment', 'overtime', 'allowance', 'ad_hoc'"
  @sources_before "'scheduled_class', 'appointment_slot', 'finance_payment', 'finance_reversal', 'manual'"
  @sources @sources_before <> ", 'rule', 'pay_item'"

  def change do
    # ── Rules ───────────────────────────────────────────────────────────────
    alter table(:coach_pay_rules) do
      add :frequency, :string
      add :amount_basis, :string, null: false, default: "gross"
    end

    create constraint(:coach_pay_rules, :coach_pay_rules_basis_check,
             check: "amount_basis IN ('gross', 'net')"
           )

    replace_check(
      :coach_pay_rules,
      :coach_pay_rules_kind_check,
      "kind IN (#{@kinds})",
      "kind IN (#{@kinds_before})"
    )

    replace_check(
      :coach_pay_rules,
      :coach_pay_rules_amount_check,
      amount_check("'personal_training', 'sold_by', 'own_clients', 'box_all'"),
      amount_check("'personal_training', 'sold_by'")
    )

    create constraint(:coach_pay_rules, :coach_pay_rules_frequency_check,
             check: """
             (kind = 'fixed' AND frequency IN ('monthly', 'weekly', 'daily'))
             OR (kind <> 'fixed' AND frequency IS NULL)
             """
           )

    # ── Pay items (overtime and allowances) ────────────────────────────────
    create table(:coach_pay_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :kind, :string, null: false
      add :name, :string, null: false
      add :amount_cents, :integer, null: false
      add :unit, :string, null: false
      add :roles, {:array, :string}, null: false
      add :weekly_threshold, :integer
      add :currency, :string, size: 3, null: false
      add :amount_basis, :string, null: false, default: "gross"
      add :archived_at, :utc_datetime_usec
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:coach_pay_items, :coach_pay_items_unit_check,
             check: """
             (kind = 'overtime' AND unit = 'per_hour')
             OR (kind = 'allowance' AND unit IN ('per_period', 'per_occurrence'))
             """
           )

    create constraint(:coach_pay_items, :coach_pay_items_basis_check,
             check: "amount_basis IN ('gross', 'net')"
           )

    create constraint(:coach_pay_items, :coach_pay_items_amount_check,
             check: "amount_cents BETWEEN 1 AND 10000000"
           )

    create constraint(:coach_pay_items, :coach_pay_items_threshold_check,
             check: """
             (kind = 'overtime' AND weekly_threshold BETWEEN 0 AND 168)
             OR (kind = 'allowance' AND weekly_threshold IS NULL)
             """
           )

    create constraint(:coach_pay_items, :coach_pay_items_roles_check,
             check: "cardinality(roles) > 0"
           )

    create index(:coach_pay_items, [:organization_id, :kind])

    # ── Lines and statements ───────────────────────────────────────────────
    alter table(:coach_pay_lines) do
      add :pay_item_id, references(:coach_pay_items, type: :binary_id, on_delete: :nilify_all)
      add :quantity_divisor, :integer
      add :note, :text
      add :amount_basis, :string, null: false, default: "gross"
    end

    create constraint(:coach_pay_lines, :coach_pay_lines_basis_check,
             check: "amount_basis IN ('gross', 'net')"
           )

    replace_check(
      :coach_pay_lines,
      :coach_pay_lines_kind_check,
      "kind IN (#{@line_kinds})",
      "kind IN (#{@line_kinds_before})"
    )

    replace_check(
      :coach_pay_lines,
      :coach_pay_lines_source_check,
      "source_type IN (#{@sources})",
      "source_type IN (#{@sources_before})"
    )

    create constraint(:coach_pay_lines, :coach_pay_lines_divisor_check,
             check: "quantity_divisor IS NULL OR quantity_divisor BETWEEN 1 AND 10080"
           )

    create constraint(:coach_pay_lines, :coach_pay_lines_note_check,
             check: "note IS NULL OR char_length(note) <= 500"
           )

    alter table(:coach_pay_statements) do
      add :rule_terms, :map, null: false, default: %{}
      add :gross_cents, :bigint, null: false, default: 0
      add :net_cents, :bigint, null: false, default: 0
    end

    alter table(:coach_pay_periods) do
      add :gross_cents, :bigint, null: false, default: 0
      add :net_cents, :bigint, null: false, default: 0
    end

    # ── Tenant isolation of the new table ──────────────────────────────────
    execute(
      """
      CREATE TRIGGER coach_pay_items_apply_tenant_context
      BEFORE INSERT OR UPDATE ON coach_pay_items
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """,
      "DROP TRIGGER IF EXISTS coach_pay_items_apply_tenant_context ON coach_pay_items"
    )

    execute(
      """
      CREATE POLICY coach_pay_items_tenant_policy ON coach_pay_items
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS coach_pay_items_tenant_policy ON coach_pay_items"
    )

    execute(
      "ALTER TABLE coach_pay_items ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE coach_pay_items DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE coach_pay_items FORCE ROW LEVEL SECURITY",
      "ALTER TABLE coach_pay_items NO FORCE ROW LEVEL SECURITY"
    )
  end

  defp amount_check(scopes) do
    """
    (kind = 'percent_of_sales' AND percent_bps BETWEEN 1 AND 10000
      AND sales_scope IN (#{scopes}))
    OR (kind <> 'percent_of_sales' AND amount_cents BETWEEN 1 AND 10000000)
    """
  end

  defp replace_check(table, name, check, previous) do
    # Rolled back in reverse: the new check goes, then the previous one returns.
    execute(
      "ALTER TABLE #{table} DROP CONSTRAINT #{name}",
      "ALTER TABLE #{table} ADD CONSTRAINT #{name} CHECK (#{previous})"
    )

    execute(
      "ALTER TABLE #{table} ADD CONSTRAINT #{name} CHECK (#{check})",
      "ALTER TABLE #{table} DROP CONSTRAINT #{name}"
    )
  end
end
