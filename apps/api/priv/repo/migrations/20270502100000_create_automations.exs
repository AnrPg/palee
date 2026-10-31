defmodule Palee.Repo.Migrations.CreateAutomations do
  @moduledoc """
  ADR-346: automations from ready recipes. Not a workflow builder: Palee
  ships the recipes (welcome, trial follow-up, missed classes, renewal
  reminder, birthday, win-back) and a box only switches each one on and may
  change its text, channels and delay (`box_automations`).

  `automation_deliveries` is the outbox: one row per message a recipe
  decided to send to one person (a box member or a lead), due at a time
  already moved out of the box's quiet hours. A worker claims due rows
  (`FOR UPDATE SKIP LOCKED`) and hands them to a channel adapter. The
  `trigger_ref` makes every trigger idempotent.

  `automation_member_preferences` is what a box member chose for this box:
  no automatic messages at all or not from some recipes, and the birthday
  (day and month only, never the year) they chose to share for the
  birthday greeting. Palee itself never collects a date of birth (ADR-267).
  """

  use Ecto.Migration

  @tables ~w(box_automations automation_deliveries automation_member_preferences)

  def change do
    create table(:box_automations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :recipe, :string, null: false
      add :enabled, :boolean, null: false, default: false
      add :channels, {:array, :string}, null: false, default: []
      add :delay_minutes, :integer
      add :subject, :string
      add :body, :text
      add :settings, :map, null: false, default: %{}
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:box_automations, [:organization_id, :recipe])
    create index(:box_automations, [:updated_by_id])

    create constraint(:box_automations, :box_automations_delay_check,
             check: "delay_minutes IS NULL OR (delay_minutes >= 0 AND delay_minutes <= 43200)"
           )

    create table(:automation_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :recipe, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :lead_id, references(:leads, type: :binary_id, on_delete: :delete_all)
      add :trigger_ref, :string, null: false
      # What the trigger knew that the text needs ({days}, {package}...).
      add :data, :map, null: false, default: %{}
      add :due_at, :utc_datetime_usec, null: false
      add :status, :string, null: false, default: "pending"
      add :channel, :string
      add :attempts, :integer, null: false, default: 0
      add :claimed_at, :utc_datetime_usec
      add :sent_at, :utc_datetime_usec
      add :skip_reason, :string
      add :last_error, :string
      add :external_ref, :string

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:automation_deliveries, :automation_deliveries_status_check,
             check: "status IN ('pending', 'sending', 'sent', 'skipped', 'failed', 'cancelled')"
           )

    create constraint(:automation_deliveries, :automation_deliveries_recipient_check,
             check: "(user_id IS NULL) <> (lead_id IS NULL)"
           )

    create unique_index(:automation_deliveries, [:organization_id, :recipe, :trigger_ref],
             name: :automation_deliveries_trigger_index
           )

    create index(:automation_deliveries, [:organization_id, :status, :due_at])
    create index(:automation_deliveries, [:user_id])
    create index(:automation_deliveries, [:lead_id])

    create table(:automation_member_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :opted_out_at, :utc_datetime_usec
      add :opted_out_recipes, {:array, :string}, null: false, default: []
      add :birthday_month, :integer
      add :birthday_day, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:automation_member_preferences, [:organization_id, :user_id])
    create index(:automation_member_preferences, [:user_id])

    create constraint(
             :automation_member_preferences,
             :automation_member_preferences_birthday_check,
             check:
               "(birthday_month IS NULL AND birthday_day IS NULL) OR " <>
                 "(birthday_month BETWEEN 1 AND 12 AND birthday_day BETWEEN 1 AND 31)"
           )

    for table <- @tables, do: secure(table)
  end

  defp secure(table) do
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
