defmodule Palee.Repo.Migrations.LeavingEndsBoxMembership do
  @moduledoc """
  ADR-595: leaving a box ends the box membership at once; a package already
  bought stays usable until its last day and money owed stays owed.

    * `organization_memberships.left_at` / `left_by` (`member` | `staff`):
      when the person stopped being a member of the box, and who ended it.
      The row stays `active`, so the person still reaches the box for what
      they keep (their package until `access_until`, their bills, a way back).
    * `organization_memberships.access_until`: the last day the package they
      kept lets them use the box (nil: nothing kept).
    * `memberships.status_shown` admits `former` («Πρώην μέλος»).
    * `memberships.entitlement_grace_until`: the last day of a grace the
      member is in (unpaid charge or ended package), so the member and staff
      see the same «σε χάρη ως …» line without working it out per read.
    * Notification type `box_membership_ended`: the person hears that the
      box ended their membership.

  Members who left under ADR-220 are carried over: their box membership
  ends now, keeping the last day the finance profile already has.
  """

  use Ecto.Migration

  @statuses ~w(active trial comped unpaid overdue leaving expiring paused expired cancelled no_package)
  @notification_types ~w(box_membership_ended)

  def up do
    alter table(:organization_memberships) do
      add :left_at, :utc_datetime_usec
      add :left_by, :string
      add :access_until, :date
    end

    create constraint(:organization_memberships, :organization_memberships_left_by_check,
             check: "left_by IS NULL OR left_by IN ('member', 'staff')"
           )

    create constraint(:organization_memberships, :organization_memberships_left_check,
             check:
               "(left_at IS NULL) = (left_by IS NULL) AND (left_at IS NOT NULL OR access_until IS NULL)"
           )

    replace_status_shown(@statuses ++ ["former"])

    alter table(:memberships) do
      add :entitlement_grace_until, :date
    end

    execute("""
    UPDATE organization_memberships AS om
    SET left_at = m.left_at, left_by = m.left_by, access_until = m.leaving_on
    FROM memberships AS m
    WHERE m.organization_id = om.organization_id
      AND m.user_id = om.user_id
      AND m.left_at IS NOT NULL
      AND om.left_at IS NULL
      AND NOT (om.roles::text[] && ARRAY['owner', 'admin', 'coach', 'front_desk', 'accountant', 'janitor'])
    """)

    rewrite_notification_types(&Enum.uniq(&1 ++ @notification_types))
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN (#{Enum.map_join(@notification_types, ", ", &"'#{&1}'")})"
    )

    rewrite_notification_types(&(&1 -- @notification_types))

    alter table(:memberships) do
      remove :entitlement_grace_until
    end

    execute("UPDATE memberships SET status_shown = 'cancelled' WHERE status_shown = 'former'")
    replace_status_shown(@statuses)

    drop constraint(:organization_memberships, :organization_memberships_left_check)
    drop constraint(:organization_memberships, :organization_memberships_left_by_check)

    alter table(:organization_memberships) do
      remove :access_until
      remove :left_by
      remove :left_at
    end
  end

  defp replace_status_shown(statuses) do
    drop constraint(:memberships, :memberships_status_shown_check)

    create constraint(:memberships, :memberships_status_shown_check,
             check:
               "status_shown IS NULL OR status_shown IN (#{Enum.map_join(statuses, ", ", &"'#{&1}'")})"
           )
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
