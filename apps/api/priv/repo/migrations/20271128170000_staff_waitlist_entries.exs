defmodule Palee.Repo.Migrations.StaffWaitlistEntries do
  @moduledoc """
  ADR-790 (ANR picks 1C, 2B, 2026-11-28): staff put a member on a full
  class's waitlist.

    * `bookings.waitlisted_by_id`: the staff member who did it (nil when the
      member joined the list themselves). A place offered from such an entry
      follows the staff placement rules (approved at once).
    * `bookings.waitlist_front_at`: set when staff chose «Πρώτος στη σειρά»;
      these entries come before everyone else, the latest first.
    * notification type `booking_waitlisted_by_staff`, the member's notice.
  """

  use Ecto.Migration

  @types ~w(booking_waitlisted_by_staff)

  def up do
    alter table(:bookings) do
      add :waitlisted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :waitlist_front_at, :utc_datetime_usec
    end

    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN (#{Enum.map_join(@types, ", ", &"'#{&1}'")})"
    )

    rewrite_notification_types(&(&1 -- @types))

    alter table(:bookings) do
      remove :waitlist_front_at
      remove :waitlisted_by_id
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
