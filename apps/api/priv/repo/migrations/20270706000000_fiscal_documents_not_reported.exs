defmodule Palee.Repo.Migrations.FiscalDocumentsNotReported do
  @moduledoc """
  ADR-452: notification type `fiscal_documents_not_reported` for the staff
  who manage billing, when documents were refused by the tax authority or
  ran out of attempts.
  """

  use Ecto.Migration

  @types ~w(fiscal_documents_not_reported)

  def up, do: rewrite_notification_types(&Enum.uniq(&1 ++ @types))

  def down do
    execute("DELETE FROM notifications WHERE type IN ('fiscal_documents_not_reported')")
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
