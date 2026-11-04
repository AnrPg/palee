defmodule Palee.Repo.Migrations.CoachPayItemFrequencyAndSkips do
  @moduledoc """
  ADR-510 (product owner, 2026-11-04): allowances that recur are added to
  every calculated period by themselves.

    * `coach_pay_items.frequency` – how often a recurring allowance
      (`unit = per_period`) pays its amount: once per pay period
      (`period`), or per `daily`, `weekly` or `monthly`, prorated by the
      period's days like fixed pay. Existing recurring allowances become
      `period`. Every other item has none.
    * `coach_pay_item_skips` – a recurring allowance taken off one person
      for one period; the calculation leaves it out until it is put back.
  """

  use Ecto.Migration

  def change do
    alter table(:coach_pay_items) do
      add :frequency, :string
    end

    execute(
      "UPDATE coach_pay_items SET frequency = 'period' WHERE kind = 'allowance' AND unit = 'per_period'",
      "SELECT 1"
    )

    create constraint(:coach_pay_items, :coach_pay_items_frequency_check,
             check: """
             (kind = 'allowance' AND unit = 'per_period'
               AND frequency IN ('period', 'daily', 'weekly', 'monthly'))
             OR (NOT (kind = 'allowance' AND unit = 'per_period') AND frequency IS NULL)
             """
           )

    create table(:coach_pay_item_skips, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :period_id, references(:coach_pay_periods, type: :binary_id, on_delete: :delete_all),
        null: false

      add :pay_item_id, references(:coach_pay_items, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:coach_pay_item_skips, [:period_id, :user_id, :pay_item_id])
    create index(:coach_pay_item_skips, [:organization_id])
    create index(:coach_pay_item_skips, [:pay_item_id])
    create index(:coach_pay_item_skips, [:user_id])

    execute(
      """
      CREATE TRIGGER coach_pay_item_skips_apply_tenant_context
      BEFORE INSERT OR UPDATE ON coach_pay_item_skips
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """,
      "DROP TRIGGER IF EXISTS coach_pay_item_skips_apply_tenant_context ON coach_pay_item_skips"
    )

    execute(
      """
      CREATE POLICY coach_pay_item_skips_tenant_policy ON coach_pay_item_skips
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS coach_pay_item_skips_tenant_policy ON coach_pay_item_skips"
    )

    execute(
      "ALTER TABLE coach_pay_item_skips ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE coach_pay_item_skips DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE coach_pay_item_skips FORCE ROW LEVEL SECURITY",
      "ALTER TABLE coach_pay_item_skips NO FORCE ROW LEVEL SECURITY"
    )
  end
end
