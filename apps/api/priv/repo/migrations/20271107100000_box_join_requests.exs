defmodule Palee.Repo.Migrations.BoxJoinRequests do
  @moduledoc """
  ADR-552: «Ζήτα να γίνεις μέλος». A person asks a box to take them in as a
  box member while its member join link is off (or they are a former
  member); the box's staff accept or decline it. One open request per
  person and box. The person reads their own requests at any box.

  Notification types `join_requested` (to the staff), `join_request_accepted`
  and `join_request_declined` (to the person). The constraint is rewritten
  from what the database holds, so types other migrations add are kept.
  """

  use Ecto.Migration

  @types ~w(join_requested join_request_accepted join_request_declined)

  def up do
    create table(:organization_join_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "requested"
      add :decided_at, :utc_datetime_usec
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:organization_join_requests, :organization_join_requests_status_check,
             check: "status IN ('requested', 'accepted', 'declined', 'cancelled')"
           )

    create constraint(:organization_join_requests, :organization_join_requests_decided_check,
             check: "(status = 'requested') = (decided_at IS NULL)"
           )

    create unique_index(:organization_join_requests, [:organization_id, :user_id],
             name: :organization_join_requests_one_open_index,
             where: "status = 'requested'"
           )

    create index(:organization_join_requests, [:organization_id, :status, :inserted_at])
    create index(:organization_join_requests, [:user_id, :inserted_at])

    execute("""
    CREATE TRIGGER organization_join_requests_apply_tenant_context
    BEFORE INSERT OR UPDATE ON organization_join_requests
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    org = "organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid"
    me = "user_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

    # The box sees and handles its requests; the person sees their own, at any box.
    execute("""
    CREATE POLICY organization_join_requests_tenant_policy ON organization_join_requests
    FOR ALL USING (#{org}) WITH CHECK (#{org})
    """)

    execute("""
    CREATE POLICY organization_join_requests_owner_read_policy ON organization_join_requests
    FOR SELECT USING (#{me})
    """)

    execute("ALTER TABLE organization_join_requests ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE organization_join_requests FORCE ROW LEVEL SECURITY")

    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN ('join_requested', 'join_request_accepted', 'join_request_declined')"
    )

    rewrite_notification_types(&(&1 -- @types))
    drop table(:organization_join_requests)
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
