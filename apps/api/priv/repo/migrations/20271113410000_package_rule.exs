defmodule Palee.Repo.Migrations.PackageRule do
  @moduledoc """
  ADR-633: «Χωρίς πακέτο, χωρίς κράτηση». In a box that sells packages a
  client books classes only with a package (or a grace or free access with
  an end date, ADR-612). One exception: one class while their first «Το
  θέλω» waits for the desk.

    * `finance_settings.package_rule_since`: when the rule started for the
      box (set by the daily run the first time the box sells a package, and
      cleared when it sells none). The clients already training then get a
      14-day free access from the system.
    * `finance_package_requests`: the one class booked while waiting
      (`first_class_at`, `first_class_scheduled_class_id`), at most once per
      person and box; the `declined` status with its required reason.
    * `finance_member_benefits.actor_id` may be empty only for the system's
      own grants (`actor_roles = {system}`).
    * Notification types `package_requested` and `package_rule_started` (to
      the staff), `package_request_declined` and `package_rule_grace` (to
      the person). The constraint is rewritten from what the database holds.
  """

  use Ecto.Migration

  @types ~w(package_requested package_rule_started package_request_declined package_rule_grace)

  def up do
    alter table(:finance_settings) do
      add :package_rule_since, :utc_datetime_usec
    end

    alter table(:finance_package_requests) do
      add :first_class_at, :utc_datetime_usec
      add :first_class_scheduled_class_id, :binary_id
      add :decline_reason, :text
    end

    create unique_index(:finance_package_requests, [:organization_id, :user_id],
             name: :finance_package_requests_one_first_class_index,
             where: "first_class_at IS NOT NULL"
           )

    execute(
      "ALTER TABLE finance_package_requests DROP CONSTRAINT finance_package_requests_status_check"
    )

    create constraint(:finance_package_requests, :finance_package_requests_status_check,
             check: "status IN ('pending', 'activated', 'cancelled', 'lapsed', 'declined')"
           )

    create constraint(:finance_package_requests, :finance_package_requests_decline_check,
             check:
               "(status = 'declined') = (decline_reason IS NOT NULL AND length(btrim(decline_reason)) > 0)"
           )

    execute("ALTER TABLE finance_member_benefits ALTER COLUMN actor_id DROP NOT NULL")

    create constraint(:finance_member_benefits, :finance_member_benefits_actor_check,
             check: "actor_id IS NOT NULL OR actor_roles = ARRAY['system']::varchar[]"
           )

    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN (#{Enum.map_join(@types, ", ", &"'#{&1}'")})"
    )

    rewrite_notification_types(&(&1 -- @types))

    drop constraint(:finance_member_benefits, :finance_member_benefits_actor_check)
    execute("DELETE FROM finance_member_benefits WHERE actor_id IS NULL")
    execute("ALTER TABLE finance_member_benefits ALTER COLUMN actor_id SET NOT NULL")

    drop constraint(:finance_package_requests, :finance_package_requests_decline_check)

    execute(
      "ALTER TABLE finance_package_requests DROP CONSTRAINT finance_package_requests_status_check"
    )

    execute("UPDATE finance_package_requests SET status = 'cancelled' WHERE status = 'declined'")

    create constraint(:finance_package_requests, :finance_package_requests_status_check,
             check: "status IN ('pending', 'activated', 'cancelled', 'lapsed')"
           )

    drop index(:finance_package_requests, [:organization_id, :user_id],
           name: :finance_package_requests_one_first_class_index
         )

    alter table(:finance_package_requests) do
      remove :first_class_at
      remove :first_class_scheduled_class_id
      remove :decline_reason
    end

    alter table(:finance_settings) do
      remove :package_rule_since
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
