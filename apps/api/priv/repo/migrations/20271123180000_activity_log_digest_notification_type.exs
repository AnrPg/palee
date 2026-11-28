defmodule Palee.Repo.Migrations.ActivityLogDigestNotificationType do
  @moduledoc """
  ADR-760 (ANR 12B): `activity_log_digest`, the owners' morning summary of
  the box's sensitive actions of the day before.
  """

  use Ecto.Migration

  @types ~w(activity_log_digest)

  def up do
    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN (#{Enum.map_join(@types, ", ", &"'#{&1}'")})"
    )

    rewrite_notification_types(&(&1 -- @types))
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
