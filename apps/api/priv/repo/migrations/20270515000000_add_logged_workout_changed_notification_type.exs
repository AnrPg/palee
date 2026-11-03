defmodule Palee.Repo.Migrations.AddLoggedWorkoutChangedNotificationType do
  @moduledoc """
  ADR-393: notification type `logged_workout_changed`, for the people who
  already logged a score or a run of a WOD that staff then edited. The
  constraint is rewritten from what the database holds, so types other
  migrations add are kept.
  """

  use Ecto.Migration

  @types ~w(logged_workout_changed)

  def up, do: rewrite_notification_types(&Enum.uniq(&1 ++ @types))

  def down do
    execute("DELETE FROM notifications WHERE type IN ('logged_workout_changed')")
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
