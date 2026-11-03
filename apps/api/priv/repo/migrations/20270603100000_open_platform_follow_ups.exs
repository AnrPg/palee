defmodule Palee.Repo.Migrations.OpenPlatformFollowUps do
  @moduledoc """
  ADR-379/380 follow-ups (2026-11-03):

    * `audience_connections.unsubscribe_token_hash` – the secret token of the
      address Mailchimp or Brevo calls when someone unsubscribes on their side
      (stored as a SHA-256 hash, shown once), and the SECURITY DEFINER
      `palee_audience_connection_lookup(uuid)` that resolves that address's
      box before its tenant session exists (the token is checked inside it);
    * notification type `webhook_disabled`, for the staff who manage
      settings when Palee turns off a webhook that keeps failing.

  The notification constraint is rewritten from what the database holds, so
  types other migrations add are kept.
  """

  use Ecto.Migration

  @types ~w(webhook_disabled)

  def up do
    alter table(:audience_connections) do
      add :unsubscribe_token_hash, :binary
    end

    execute("""
    CREATE OR REPLACE FUNCTION palee_audience_connection_lookup(connection_id uuid)
    RETURNS uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT c.organization_id
      FROM public.audience_connections c
      JOIN public.organizations o ON o.id = c.organization_id
      WHERE c.id = connection_id AND o.status = 'active'
      LIMIT 1
    $$
    """)

    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN ('webhook_disabled')")
    rewrite_notification_types(&(&1 -- @types))
    execute("DROP FUNCTION IF EXISTS palee_audience_connection_lookup(uuid)")

    alter table(:audience_connections) do
      remove :unsubscribe_token_hash
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
