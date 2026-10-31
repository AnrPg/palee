defmodule Palee.Repo.Migrations.CardSurchargeSettings do
  @moduledoc """
  ADR-340 (CP-A5): the box's optional card surcharge for members.

    * `payment_surcharge_settings`: one row per box, off until the owner
      turns it on; checked against the law of the box's country on save.
    * `payment_methods.card_funding` / `card_country` / `card_commercial`:
      what the provider told about a saved card (credit or debit, issuing
      country, commercial), so a surcharge is added only to a card the law
      allows it on. Unknown stays NULL and counts against a surcharge.
  """

  use Ecto.Migration

  def change do
    create table(:payment_surcharge_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :enabled, :boolean, null: false, default: false
      add :channels, {:array, :string}, null: false, default: []
      add :percent_bps, :integer, null: false, default: 0
      add :fixed_cents, :integer, null: false, default: 0
      add :region_code, :string, size: 10
      add :at_cost_confirmed, :boolean, null: false, default: false
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:payment_surcharge_settings, [:organization_id])

    create constraint(:payment_surcharge_settings, :payment_surcharge_settings_amounts_check,
             check:
               "percent_bps BETWEEN 0 AND 1000 AND fixed_cents BETWEEN 0 AND 10000"
           )

    create constraint(:payment_surcharge_settings, :payment_surcharge_settings_channels_check,
             check: "channels <@ ARRAY['online', 'terminal', 'desk']::varchar[]"
           )

    alter table(:payment_methods) do
      add :card_funding, :string, size: 10
      add :card_country, :string, size: 2
      add :card_commercial, :boolean
    end

    create constraint(:payment_methods, :payment_methods_card_funding_check,
             check: "card_funding IS NULL OR card_funding IN ('credit', 'debit', 'prepaid')"
           )

    execute(
      """
      CREATE TRIGGER payment_surcharge_settings_apply_tenant_context
      BEFORE INSERT OR UPDATE ON payment_surcharge_settings
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """,
      "DROP TRIGGER IF EXISTS payment_surcharge_settings_apply_tenant_context ON payment_surcharge_settings"
    )

    execute(
      """
      CREATE POLICY payment_surcharge_settings_tenant_policy ON payment_surcharge_settings
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS payment_surcharge_settings_tenant_policy ON payment_surcharge_settings"
    )

    execute(
      "ALTER TABLE payment_surcharge_settings ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE payment_surcharge_settings DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE payment_surcharge_settings FORCE ROW LEVEL SECURITY",
      "ALTER TABLE payment_surcharge_settings NO FORCE ROW LEVEL SECURITY"
    )
  end
end
