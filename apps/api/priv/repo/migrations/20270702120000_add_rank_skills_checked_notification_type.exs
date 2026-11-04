defmodule Palee.Repo.Migrations.AddRankSkillsCheckedNotificationType do
  @moduledoc """
  ADR-400 follow-up: notification type `rank_skills_checked`, the calm
  grouped notice of the skills a coach ticked for a person. The
  constraint is rewritten from what the database holds, so types other
  migrations add are kept.
  """

  use Ecto.Migration

  @types ~w(rank_skills_checked)

  def up, do: rewrite_notification_types(&Enum.uniq(&1 ++ @types))

  def down do
    execute("DELETE FROM notifications WHERE type IN ('rank_skills_checked')")
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
