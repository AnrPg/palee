defmodule Palee.Repo.Migrations.PackageWaitBookings do
  @moduledoc """
  ADR-717: «Κρατήσεις πριν την πληρωμή». ADR-633 let a person whose «Το
  θέλω» waits for the front desk book ONE class. The box now chooses how
  many (default 3, 0 = none until the desk activates the package).

    * `finance_settings.package_wait_bookings`: the box's number (0–20).
    * `finance_package_wait_bookings`: one row per class booked while
      waiting, counted per person and box for good (a new request does not
      start the count again). It replaces the one-class columns on
      `finance_package_requests`, whose rows are copied over.
  """

  use Ecto.Migration

  def up do
    alter table(:finance_settings) do
      add :package_wait_bookings, :integer, null: false, default: 3
    end

    create constraint(:finance_settings, :finance_settings_package_wait_bookings_check,
             check: "package_wait_bookings BETWEEN 0 AND 20"
           )

    create table(:finance_package_wait_bookings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Kept when the request goes, so the count never starts again.
      add :package_request_id,
          references(:finance_package_requests, type: :binary_id, on_delete: :nilify_all)

      add :scheduled_class_id, :binary_id, null: false
      add :booked_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # The same class booked again (after a cancel) counts once.
    create unique_index(
             :finance_package_wait_bookings,
             [:organization_id, :user_id, :scheduled_class_id],
             name: :finance_package_wait_bookings_one_per_class_index
           )

    create index(:finance_package_wait_bookings, [:package_request_id])
    create index(:finance_package_wait_bookings, [:user_id])

    execute("""
    CREATE TRIGGER finance_package_wait_bookings_apply_tenant_context
    BEFORE INSERT OR UPDATE ON finance_package_wait_bookings
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY finance_package_wait_bookings_tenant_policy ON finance_package_wait_bookings
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE finance_package_wait_bookings ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE finance_package_wait_bookings FORCE ROW LEVEL SECURITY")

    execute("""
    INSERT INTO finance_package_wait_bookings
      (id, organization_id, user_id, package_request_id, scheduled_class_id, booked_at, inserted_at)
    SELECT gen_random_uuid(), organization_id, user_id, id, first_class_scheduled_class_id,
           first_class_at, first_class_at
    FROM finance_package_requests
    WHERE first_class_at IS NOT NULL AND first_class_scheduled_class_id IS NOT NULL
    """)

    drop index(:finance_package_requests, [:organization_id, :user_id],
           name: :finance_package_requests_one_first_class_index
         )

    alter table(:finance_package_requests) do
      remove :first_class_at
      remove :first_class_scheduled_class_id
    end
  end

  def down do
    alter table(:finance_package_requests) do
      add :first_class_at, :utc_datetime_usec
      add :first_class_scheduled_class_id, :binary_id
    end

    flush()

    # Back to one class: the earliest one each person booked.
    execute("""
    UPDATE finance_package_requests r
    SET first_class_at = w.booked_at, first_class_scheduled_class_id = w.scheduled_class_id
    FROM (
      SELECT DISTINCT ON (organization_id, user_id)
             package_request_id, booked_at, scheduled_class_id
      FROM finance_package_wait_bookings
      WHERE package_request_id IS NOT NULL
      ORDER BY organization_id, user_id, booked_at
    ) w
    WHERE r.id = w.package_request_id
    """)

    create unique_index(:finance_package_requests, [:organization_id, :user_id],
             name: :finance_package_requests_one_first_class_index,
             where: "first_class_at IS NOT NULL"
           )

    drop table(:finance_package_wait_bookings)

    drop constraint(:finance_settings, :finance_settings_package_wait_bookings_check)

    alter table(:finance_settings) do
      remove :package_wait_bookings
    end
  end
end
