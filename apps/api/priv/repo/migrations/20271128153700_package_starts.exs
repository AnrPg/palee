defmodule Palee.Repo.Migrations.PackageStarts do
  @moduledoc """
  ADR-795: when a package starts, and the money confirmations.

    * `finance_settings.package_starts_with`: `first_session` (default, the
      period and the next payment count from the member's first completed
      class or WOD) or `payment` (from the purchase or the desk payment).
    * `membership_package_subscriptions.awaiting_first_session`: the package
      was given and waits for that first class or WOD.
    * `finance_package_starts`: one row per waiting subscription, the lineage
      of its start (bought name, the session, the changes found, who
      acknowledged them and when).
    * `finance_confirmation_skips`: «Να μην εμφανιστεί ξανά σήμερα» per person,
      box, question and box day.
    * The per-package «Έναρξη ισχύος» (`terms.validity_starts`) left the
      catalog (ADR-383: dropped when a package is read or saved again);
      subscriptions sold before keep their own copy.
    * Notification type `package_start_review`.
  """

  use Ecto.Migration

  @types ~w(package_start_review)

  def up do
    alter table(:finance_settings) do
      # NULL: the platform default (`PackageStart.default_mode/0`,
      # `first_session`); a box that chooses stores its choice.
      add :package_starts_with, :string
    end

    create constraint(:finance_settings, :finance_settings_package_starts_with_check,
             check: "package_starts_with IN ('first_session', 'payment')"
           )

    alter table(:membership_package_subscriptions) do
      add :awaiting_first_session, :boolean, null: false, default: false
    end

    create index(:membership_package_subscriptions, [:organization_id],
             where: "awaiting_first_session",
             name: :membership_package_subscriptions_awaiting_first_session_index
           )

    create table(:finance_package_starts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :subscription_id,
          references(:membership_package_subscriptions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :package_name, :string, null: false
      add :waiting_since, :date, null: false
      add :status, :string, null: false, default: "waiting"
      add :session_kind, :string
      add :session_id, :binary_id
      add :session_on, :date
      add :severity, :string
      add :changes, {:array, :map}, null: false, default: []
      add :started_on, :date
      add :reviewed_at, :utc_datetime_usec
      add :acknowledged_at, :utc_datetime_usec
      add :acknowledged_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:finance_package_starts, [:subscription_id])
    create index(:finance_package_starts, [:organization_id, :status])
    create index(:finance_package_starts, [:user_id])
    create index(:finance_package_starts, [:membership_id])
    create index(:finance_package_starts, [:acknowledged_by_id])

    create constraint(:finance_package_starts, :finance_package_starts_status_check,
             check: "status IN ('waiting', 'review', 'started')"
           )

    create constraint(:finance_package_starts, :finance_package_starts_session_kind_check,
             check: "session_kind IS NULL OR session_kind IN ('class', 'workout')"
           )

    create constraint(:finance_package_starts, :finance_package_starts_severity_check,
             check: "severity IS NULL OR severity IN ('important', 'serious', 'warning')"
           )

    create table(:finance_confirmation_skips, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :skip_on, :date, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:finance_confirmation_skips, [:organization_id, :user_id, :kind, :skip_on])

    create index(:finance_confirmation_skips, [:user_id])

    for table <- ~w(finance_package_starts finance_confirmation_skips) do
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
    execute("DELETE FROM notifications WHERE type IN ('package_start_review')")
    rewrite_notification_types(&(&1 -- @types))
    drop table(:finance_confirmation_skips)
    drop table(:finance_package_starts)

    drop index(:membership_package_subscriptions, [:organization_id],
           name: :membership_package_subscriptions_awaiting_first_session_index
         )

    alter table(:membership_package_subscriptions) do
      remove :awaiting_first_session
    end

    drop constraint(:finance_settings, :finance_settings_package_starts_with_check)

    alter table(:finance_settings) do
      remove :package_starts_with
    end
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
