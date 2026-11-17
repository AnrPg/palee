defmodule Palee.Repo.Migrations.PackageRemovals do
  @moduledoc """
  ADR-660: staff remove a member's package completely («Αφαίρεση πακέτου»).

    * `membership_package_subscriptions.removed_on`: the box day staff
      removed the package. A removed subscription is `cancelled` and gives
      nothing from that day on; the member's status reads «Χωρίς πακέτο».
    * `finance_package_removals`: one row per removal, with who removed it
      (`actor_id`, `actor_roles`), why (`reason`, and whether the member is
      shown it), what was done with an unpaid invoice nobody paid anything
      on (`invoice_choice`: `void` or `keep`; nil when there was none), the
      invoices voided (`voided_invoices`: id, the status and referral
      rewards to give back on undo) and what the removal changed on a
      member who left (`previous_leaving_on`, `previous_expires_on`).
      `undo_until` closes the short undo; then the removal is `settled`
      (upcoming bookings cancelled, the member told) unless it was undone.
    * Notification type `package_removed`.

  The table is tenant-scoped (RLS) and goes with its membership.
  """

  use Ecto.Migration

  @notification_types ~w(package_removed)

  def up do
    alter table(:membership_package_subscriptions) do
      add :removed_on, :date
    end

    create constraint(:membership_package_subscriptions, :subscriptions_removed_check,
             check: "removed_on IS NULL OR status = 'cancelled'"
           )

    create table(:finance_package_removals, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :subscription_id,
          references(:membership_package_subscriptions,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      # The member and the staff member as they were: no foreign key, so the
      # lineage survives an account being deleted.
      add :user_id, :binary_id, null: false
      add :package_name, :string, null: false
      add :previous_status, :string, null: false
      add :removed_on, :date, null: false
      add :actor_id, :binary_id, null: false
      add :actor_roles, {:array, :string}, null: false, default: []
      add :reason, :text
      add :reason_shared, :boolean, null: false, default: false
      add :invoice_choice, :string
      add :voided_invoices, {:array, :map}, null: false, default: []
      add :previous_leaving_on, :date
      add :previous_expires_on, :date
      add :leaving_changed, :boolean, null: false, default: false
      add :undo_until, :utc_datetime_usec, null: false
      add :undone_at, :utc_datetime_usec
      add :undone_by_id, :binary_id
      add :settled_at, :utc_datetime_usec
      add :cancelled_bookings, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:finance_package_removals, :finance_package_removals_choice_check,
             check: "invoice_choice IS NULL OR invoice_choice IN ('void', 'keep')"
           )

    create constraint(:finance_package_removals, :finance_package_removals_reason_check,
             check: "reason IS NULL OR char_length(reason) <= 500"
           )

    create constraint(:finance_package_removals, :finance_package_removals_outcome_check,
             check: "undone_at IS NULL OR settled_at IS NULL"
           )

    create constraint(:finance_package_removals, :finance_package_removals_undo_check,
             check: "(undone_at IS NULL) = (undone_by_id IS NULL)"
           )

    create index(:finance_package_removals, [:organization_id, :membership_id, :inserted_at])

    # One open (neither undone nor settled) removal per subscription.
    create unique_index(:finance_package_removals, [:subscription_id],
             name: :finance_package_removals_one_open_index,
             where: "undone_at IS NULL"
           )

    execute("""
    CREATE TRIGGER finance_package_removals_apply_tenant_context
    BEFORE INSERT ON finance_package_removals
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY finance_package_removals_tenant_policy ON finance_package_removals
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE finance_package_removals ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE finance_package_removals FORCE ROW LEVEL SECURITY")

    rewrite_notification_types(&Enum.uniq(&1 ++ @notification_types))
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN (#{Enum.map_join(@notification_types, ", ", &"'#{&1}'")})"
    )

    rewrite_notification_types(&(&1 -- @notification_types))
    drop table(:finance_package_removals)
    drop constraint(:membership_package_subscriptions, :subscriptions_removed_check)

    alter table(:membership_package_subscriptions) do
      remove :removed_on
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
