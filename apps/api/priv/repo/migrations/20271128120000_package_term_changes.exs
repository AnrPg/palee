defmodule Palee.Repo.Migrations.PackageTermChanges do
  @moduledoc """
  ADR-770: changes of a subscription package reach the members who already
  hold it, when staff choose so after «Αποθήκευση αλλαγών».

    * `finance_package_term_changes`: one row per saved change of a package
      that had holders: what changed (price and contract fields, before and
      after), whom it was for (`active` or `new_only`), the subscriptions
      staff left out, and who saved it.
    * `finance_subscription_term_updates`: per subscription, the terms the
      change gives it, now (`timing = now`, applied at once) or from the
      start of its next period (`next_period`, `pending` until that day).
      At most one pending update per subscription: a later change merges
      into it (the earlier pending row is `superseded`).
    * Notification type `package_terms_changed` (the member hears what
      changes and from when).
  """

  use Ecto.Migration

  @types ~w(package_terms_changed)

  def up do
    create table(:finance_package_term_changes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_package_id,
          references(:membership_packages, type: :binary_id, on_delete: :delete_all),
          null: false

      add :changed_by, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :apply_to, :string, null: false
      add :price_before_cents, :integer, null: false
      add :price_after_cents, :integer, null: false
      add :fields_before, :map, null: false, default: %{}
      add :fields_after, :map, null: false, default: %{}
      add :excluded_subscription_ids, {:array, :binary_id}, null: false, default: []
      add :holders_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:finance_package_term_changes, :finance_package_term_changes_apply_to_check,
             check: "apply_to IN ('active', 'new_only')"
           )

    create index(:finance_package_term_changes, [:membership_package_id, :inserted_at])

    create table(:finance_subscription_term_updates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :subscription_id,
          references(:membership_package_subscriptions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :term_change_id,
          references(:finance_package_term_changes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :timing, :string, null: false
      add :status, :string, null: false
      add :effective_on, :date, null: false
      # The new price (nil: the price does not change) and the new value of
      # every field that changes; `changes` is what the member is shown.
      add :price_cents, :integer
      add :fields, :map, null: false, default: %{}
      add :changes, {:array, :map}, null: false, default: []
      add :applied_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(
             :finance_subscription_term_updates,
             :finance_subscription_term_updates_timing_check,
             check: "timing IN ('now', 'next_period')"
           )

    create constraint(
             :finance_subscription_term_updates,
             :finance_subscription_term_updates_status_check,
             check: "status IN ('pending', 'applied', 'superseded')"
           )

    create unique_index(:finance_subscription_term_updates, [:subscription_id],
             name: :finance_subscription_term_updates_one_pending_index,
             where: "status = 'pending'"
           )

    create index(:finance_subscription_term_updates, [:subscription_id, :inserted_at])
    create index(:finance_subscription_term_updates, [:effective_on], where: "status = 'pending'")
    create index(:finance_subscription_term_updates, [:user_id])
    create index(:finance_subscription_term_updates, [:membership_id])
    create index(:finance_subscription_term_updates, [:term_change_id])

    for table <- ~w(finance_package_term_changes finance_subscription_term_updates) do
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

    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN ('package_terms_changed')")
    rewrite_notification_types(&(&1 -- @types))
    drop table(:finance_subscription_term_updates)
    drop table(:finance_package_term_changes)
  end

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = Regex.scan(~r/'([a-z0-9_]+)'/, definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{Enum.map_join(change.(current), ", ", &"'#{&1}'")}))"
    )
  end
end
