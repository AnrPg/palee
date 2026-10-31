defmodule Palee.Repo.Migrations.OpenPlatform do
  @moduledoc """
  ADR-378..381 (CP-F5, CP-E3): the open platform and door access control.

    * `api_keys` – per-box keys for the public API: a public `prefix`, the
      SHA-256 of the whole token (never the token), scopes, the staff member
      the key acts for, rotation (the old secret stays valid until
      `previous_expires_at`) and revocation (ADR-378);
    * `idempotency_records` – ADR-300's generic `Idempotency-Key` store: the
      first answer of a command, replayed for the same key and body;
    * `webhook_endpoints`, `webhook_deliveries` (the outbox) and
      `webhook_delivery_attempts` (insert-only log) – signed webhooks with
      retries, a delivery log and replay (ADR-379);
    * `audience_connections`, `integration_marketing_consents` and
      `audience_members` – Mailchimp/Brevo audience sync of members who
      agreed to marketing email (ADR-380);
    * `door_controllers` and `access_events` – door controllers per branch and
      the audit log of who went in, who was refused and what the door
      reported (ADR-381).

  Every table is tenant data with forced row-level security. Three narrow
  SECURITY DEFINER look-ups resolve a tenant before its context exists: an
  API key by its public prefix, a door controller by id (provider events),
  and the organizations with webhook deliveries due (the sweep).
  """

  use Ecto.Migration

  @tables ~w(api_keys idempotency_records webhook_endpoints webhook_deliveries
             webhook_delivery_attempts audience_connections integration_marketing_consents
             audience_members door_controllers access_events)

  def up do
    create table(:api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, size: 80, null: false
      add :prefix, :string, size: 32, null: false
      add :secret_hash, :binary, null: false
      add :previous_secret_hash, :binary
      add :previous_expires_at, :utc_datetime_usec
      add :scopes, {:array, :string}, null: false, default: []
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :last_used_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :rotated_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :revoked_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:api_keys, [:prefix])
    create unique_index(:api_keys, [:id, :organization_id], name: :api_keys_id_organization_index)
    create index(:api_keys, [:organization_id, :revoked_at])

    create constraint(:api_keys, :api_keys_check,
             check: "cardinality(scopes) > 0 AND octet_length(secret_hash) = 32"
           )

    create table(:idempotency_records, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :principal, :string, size: 120, null: false
      add :key, :string, size: 255, null: false
      add :operation, :string, size: 120, null: false
      add :request_hash, :string, size: 64, null: false
      add :state, :string, null: false, default: "in_progress"
      add :response_status, :integer
      add :response_body, :map
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:idempotency_records, [:organization_id, :principal, :key])
    create index(:idempotency_records, [:expires_at])

    create constraint(:idempotency_records, :idempotency_records_check,
             check:
               "state IN ('in_progress', 'completed') AND (state = 'in_progress' OR response_status IS NOT NULL)"
           )

    create table(:webhook_endpoints, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :url, :string, size: 2000, null: false
      add :description, :string, size: 200
      add :events, {:array, :string}, null: false, default: []
      add :secret, :binary, null: false
      add :previous_secret, :binary
      add :previous_secret_expires_at, :utc_datetime_usec
      add :status, :string, null: false, default: "active"
      add :source, :string, null: false, default: "staff"
      add :api_key_id, :binary_id
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :consecutive_failures, :integer, null: false, default: 0
      add :disabled_reason, :string, size: 60
      add :last_success_at, :utc_datetime_usec
      add :last_failure_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    # A subscription made through the API (Zapier REST hooks) goes with its key.
    execute("""
    ALTER TABLE webhook_endpoints
    ADD CONSTRAINT webhook_endpoints_api_key_fkey
    FOREIGN KEY (api_key_id, organization_id)
    REFERENCES api_keys (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:webhook_endpoints, [:id, :organization_id],
             name: :webhook_endpoints_id_organization_index
           )

    create index(:webhook_endpoints, [:organization_id, :status])

    create constraint(:webhook_endpoints, :webhook_endpoints_check,
             check: """
             status IN ('active', 'disabled') AND source IN ('staff', 'api')
             AND cardinality(events) > 0 AND consecutive_failures >= 0
             AND (source = 'staff' OR api_key_id IS NOT NULL)
             """
           )

    create table(:webhook_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :endpoint_id, :binary_id, null: false
      add :event_id, :binary_id, null: false
      add :event_type, :string, size: 80, null: false
      add :payload, :map, null: false
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec
      add :claimed_at, :utc_datetime_usec
      add :last_status_code, :integer
      add :last_error, :string, size: 500
      add :delivered_at, :utc_datetime_usec
      add :replay_of_id, :binary_id
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE webhook_deliveries
    ADD CONSTRAINT webhook_deliveries_endpoint_fkey
    FOREIGN KEY (endpoint_id, organization_id)
    REFERENCES webhook_endpoints (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:webhook_deliveries, [:id, :organization_id],
             name: :webhook_deliveries_id_organization_index
           )

    create index(:webhook_deliveries, [:next_attempt_at],
             where: "status = 'pending'",
             name: :webhook_deliveries_due_index
           )

    create index(:webhook_deliveries, [:endpoint_id, :inserted_at])

    create constraint(:webhook_deliveries, :webhook_deliveries_check,
             check: """
             status IN ('pending', 'succeeded', 'failed') AND attempts >= 0
             AND (status <> 'pending' OR next_attempt_at IS NOT NULL)
             """
           )

    create table(:webhook_delivery_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :delivery_id, :binary_id, null: false
      add :attempt, :integer, null: false
      add :outcome, :string, null: false
      add :status_code, :integer
      add :error, :string, size: 500
      add :response_excerpt, :string, size: 500
      add :duration_ms, :integer
      add :started_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE webhook_delivery_attempts
    ADD CONSTRAINT webhook_delivery_attempts_delivery_fkey
    FOREIGN KEY (delivery_id, organization_id)
    REFERENCES webhook_deliveries (id, organization_id) ON DELETE CASCADE
    """)

    create index(:webhook_delivery_attempts, [:delivery_id, :attempt])

    create constraint(:webhook_delivery_attempts, :webhook_delivery_attempts_check,
             check: "outcome IN ('succeeded', 'failed', 'gone', 'blocked')"
           )

    create table(:audience_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :provider, :string, null: false
      add :list_id, :string, size: 100, null: false
      add :credentials, :binary
      add :status, :string, null: false, default: "active"
      add :last_error, :string, size: 500
      add :last_synced_at, :utc_datetime_usec
      add :sync_requested_at, :utc_datetime_usec
      add :claimed_at, :utc_datetime_usec
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:audience_connections, [:organization_id])

    create unique_index(:audience_connections, [:id, :organization_id],
             name: :audience_connections_id_organization_index
           )

    create constraint(:audience_connections, :audience_connections_check,
             check: """
             provider IN ('sandbox', 'mailchimp', 'brevo') AND status IN ('active', 'invalid')
             AND (provider = 'sandbox' OR credentials IS NOT NULL)
             """
           )

    create table(:integration_marketing_consents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :channel, :string, null: false, default: "email"
      add :granted_at, :utc_datetime_usec
      add :withdrawn_at, :utc_datetime_usec
      add :source, :string, size: 40, null: false
      add :text_version, :string, size: 40, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:integration_marketing_consents, [:organization_id, :user_id, :channel])

    create constraint(:integration_marketing_consents, :integration_marketing_consents_check,
             check: "channel IN ('email') AND (granted_at IS NOT NULL OR withdrawn_at IS NOT NULL)"
           )

    create table(:audience_members, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :connection_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :email_hash, :string, size: 64, null: false
      add :status, :string, null: false
      add :synced_at, :utc_datetime_usec, null: false
      add :last_error, :string, size: 300
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE audience_members
    ADD CONSTRAINT audience_members_connection_fkey
    FOREIGN KEY (connection_id, organization_id)
    REFERENCES audience_connections (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:audience_members, [:connection_id, :user_id])

    create constraint(:audience_members, :audience_members_check,
             check: "status IN ('subscribed', 'unsubscribed', 'failed')"
           )

    create table(:door_controllers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :location_id, :binary_id, null: false
      add :name, :string, size: 80, null: false
      add :provider, :string, null: false
      add :settings, :map, null: false, default: %{}
      add :rules, :map, null: false, default: %{}
      add :credentials, :binary
      add :event_token_hash, :binary
      add :status, :string, null: false, default: "active"
      add :last_error, :string, size: 500
      add :last_seen_at, :utc_datetime_usec
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE door_controllers
    ADD CONSTRAINT door_controllers_location_fkey
    FOREIGN KEY (location_id, organization_id)
    REFERENCES facility_locations (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:door_controllers, [:id, :organization_id],
             name: :door_controllers_id_organization_index
           )

    create index(:door_controllers, [:organization_id, :location_id])

    create constraint(:door_controllers, :door_controllers_check,
             check: """
             provider IN ('sandbox', 'shelly', 'kisi') AND status IN ('active', 'disabled', 'invalid')
             AND (provider = 'sandbox' OR credentials IS NOT NULL)
             """
           )

    create table(:access_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :door_controller_id, :binary_id
      add :location_id, :binary_id
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :reason, :string, size: 60, null: false
      add :method, :string, size: 20
      add :provider_event, :string, size: 80
      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE access_events
    ADD CONSTRAINT access_events_door_fkey
    FOREIGN KEY (door_controller_id, organization_id)
    REFERENCES door_controllers (id, organization_id) ON DELETE CASCADE
    """)

    create index(:access_events, [:organization_id, :occurred_at])
    create index(:access_events, [:user_id, :occurred_at])

    create constraint(:access_events, :access_events_check,
             check: """
             kind IN ('granted', 'denied', 'unlock_failed', 'staff_unlock', 'door_event')
             AND (method IS NULL OR method IN ('qr', 'nfc', 'staff', 'provider'))
             """
           )

    for table <- @tables do
      execute("""
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """)

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end

    lookups()
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_api_key_lookup(text)")
    execute("DROP FUNCTION IF EXISTS palee_door_controller_lookup(uuid)")
    execute("DROP FUNCTION IF EXISTS palee_webhook_due_organizations(timestamp)")

    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))
  end

  defp lookups do
    # A request carries only the key; its tenant comes from the public prefix.
    # Never the hash: the key is verified inside the tenant's own session.
    execute("""
    CREATE OR REPLACE FUNCTION palee_api_key_lookup(key_prefix text)
    RETURNS TABLE (id uuid, organization_id uuid)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT k.id, k.organization_id
      FROM public.api_keys k
      JOIN public.organizations o ON o.id = k.organization_id
      WHERE k.prefix = key_prefix
        AND k.revoked_at IS NULL
        AND o.status = 'active'
      LIMIT 1
    $$
    """)

    # A door controller's own events (Shelly actions, Kisi webhooks) name the
    # controller; its token is checked inside the tenant's session.
    execute("""
    CREATE OR REPLACE FUNCTION palee_door_controller_lookup(controller_id uuid)
    RETURNS uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT d.organization_id
      FROM public.door_controllers d
      JOIN public.organizations o ON o.id = d.organization_id
      WHERE d.id = controller_id AND o.status = 'active'
      LIMIT 1
    $$
    """)

    # The minute sweep visits only boxes with something to send.
    execute("""
    CREATE OR REPLACE FUNCTION palee_webhook_due_organizations(due_at timestamp)
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT DISTINCT d.organization_id
      FROM public.webhook_deliveries d
      WHERE d.status = 'pending' AND d.next_attempt_at <= due_at
      LIMIT 500
    $$
    """)
  end
end
