defmodule Palee.Repo.Migrations.CreateChannels do
  @moduledoc """
  ADR-348/349: SMS, Viber and WhatsApp messages from the box to its members
  and leads (CP-C3).

    * `channel_connections` – one per organization: the provider, the
      box's own credentials (the secret encrypted with `DataCipher`) or the
      Palee-managed account, the senders, the monthly budget cap and quiet
      hours;
    * `channel_contacts` – a member's or lead's mobile number (E.164) and
      language in this box; a STOP reply marks it opted out;
    * `channel_consents` – per contact, channel and purpose (`service`,
      `marketing`): when it was granted or withdrawn, and where;
    * `channel_templates` – the box's own wording of a message, per
      language, and the provider's approved WhatsApp template;
    * `channel_messages` – the outbox: one row per message, idempotent per
      box, with its state, provider id, segments and cost;
    * `channel_message_events` – insert-only log of attempts and delivery
      receipts (deduplicated by the provider's event key).
  """

  use Ecto.Migration

  @tables ~w(channel_connections channel_contacts channel_consents channel_templates
             channel_messages channel_message_events)

  def up do
    create table(:channel_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :provider, :string, null: false
      add :account_mode, :string, null: false, default: "palee"
      add :account_id, :string, size: 120
      add :secret, :binary
      add :base_url, :string, size: 200
      add :sms_sender, :string, size: 20
      add :viber_sender, :string, size: 60
      add :whatsapp_sender, :string, size: 30
      add :channels, {:array, :string}, null: false, default: []
      add :channel_order, {:array, :string}, null: false, default: ["sms", "viber", "whatsapp"]
      add :default_country, :string, size: 2, null: false, default: "GR"
      add :monthly_budget_cents, :integer, null: false, default: 2000
      add :currency, :string, size: 3, null: false, default: "EUR"
      add :quiet_start_minute, :integer
      add :quiet_end_minute, :integer
      add :webhook_salt, :binary
      add :status, :string, null: false, default: "active"
      add :error_code, :string, size: 60
      add :last_error, :string, size: 500
      add :checked_at, :utc_datetime_usec
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:channel_connections, [:organization_id])

    create constraint(:channel_connections, :channel_connections_check,
             check: """
             provider IN ('sandbox', 'brevo')
             AND account_mode IN ('own', 'palee')
             AND status IN ('active', 'invalid')
             AND channels <@ ARRAY['sms', 'viber', 'whatsapp']::varchar[]
             AND monthly_budget_cents >= 0
             AND (quiet_start_minute IS NULL OR quiet_start_minute BETWEEN 0 AND 1439)
             AND (quiet_end_minute IS NULL OR quiet_end_minute BETWEEN 0 AND 1439)
             AND (provider = 'sandbox' OR account_mode = 'palee' OR secret IS NOT NULL)
             """
           )

    create table(:channel_contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :lead_id, :binary_id
      add :phone_e164, :string, size: 16, null: false
      add :locale, :string, size: 10, null: false, default: "el"
      add :opted_out_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:channel_contacts, [:id, :organization_id],
             name: :channel_contacts_id_organization_index
           )

    create unique_index(:channel_contacts, [:organization_id, :user_id],
             where: "user_id IS NOT NULL",
             name: :channel_contacts_user_index
           )

    create unique_index(:channel_contacts, [:organization_id, :lead_id],
             where: "lead_id IS NOT NULL",
             name: :channel_contacts_lead_index
           )

    create index(:channel_contacts, [:organization_id, :phone_e164])

    create constraint(:channel_contacts, :channel_contacts_check,
             check: """
             (user_id IS NULL) <> (lead_id IS NULL)
             AND phone_e164 ~ '^\\+[1-9][0-9]{7,14}$'
             """
           )

    create table(:channel_consents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :contact_id, :binary_id, null: false
      add :channel, :string, null: false
      add :purpose, :string, null: false
      add :granted_at, :utc_datetime_usec
      add :withdrawn_at, :utc_datetime_usec
      add :source, :string, null: false
      add :text_version, :string, size: 40
      add :recorded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE channel_consents
    ADD CONSTRAINT channel_consents_contact_fkey
    FOREIGN KEY (contact_id, organization_id)
    REFERENCES channel_contacts (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:channel_consents, [:contact_id, :channel, :purpose])

    create constraint(:channel_consents, :channel_consents_check,
             check: """
             channel IN ('sms', 'viber', 'whatsapp') AND purpose IN ('service', 'marketing')
             AND source IN ('person', 'staff', 'form', 'import', 'stop_keyword')
             """
           )

    create table(:channel_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :key, :string, size: 60, null: false
      add :locale, :string, size: 10, null: false
      add :channel, :string, null: false, default: "any"
      add :body, :string, size: 1000, null: false
      add :provider_template_id, :string, size: 120
      add :variable_names, {:array, :string}, null: false, default: []
      add :approval_status, :string, null: false, default: "none"
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:channel_templates, [:organization_id, :key, :locale, :channel])

    create constraint(:channel_templates, :channel_templates_check,
             check: """
             channel IN ('any', 'whatsapp')
             AND approval_status IN ('none', 'pending', 'approved', 'rejected')
             AND (channel <> 'whatsapp' OR approval_status <> 'approved'
                  OR provider_template_id IS NOT NULL)
             """
           )

    create table(:channel_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :contact_id, :binary_id, null: false
      add :channel, :string, null: false
      add :purpose, :string, null: false
      add :template_key, :string, size: 60, null: false
      add :locale, :string, size: 10, null: false
      add :body, :string, size: 1600, null: false
      add :template_values, {:array, :string}, null: false, default: []
      add :to_phone, :string, size: 16, null: false
      add :idempotency_key, :string, size: 120, null: false
      add :status, :string, null: false, default: "queued"
      add :hold_reason, :string, size: 30
      add :urgent, :boolean, null: false, default: false
      add :attempts, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec
      add :claimed_at, :utc_datetime_usec
      add :provider, :string, null: false
      add :account_mode, :string, null: false
      add :provider_message_id, :string, size: 120
      add :segments, :integer, null: false, default: 1
      add :estimated_cost_cents, :integer, null: false, default: 0
      add :cost_cents, :integer
      add :currency, :string, size: 3, null: false, default: "EUR"
      add :error_code, :string, size: 60
      add :error_message, :string, size: 500
      add :source, :string, null: false
      add :source_ref, :string, size: 120
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :sent_at, :utc_datetime_usec
      add :delivered_at, :utc_datetime_usec
      add :failed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE channel_messages
    ADD CONSTRAINT channel_messages_contact_fkey
    FOREIGN KEY (contact_id, organization_id)
    REFERENCES channel_contacts (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:channel_messages, [:id, :organization_id],
             name: :channel_messages_id_organization_index
           )

    create unique_index(:channel_messages, [:organization_id, :idempotency_key])

    create unique_index(:channel_messages, [:provider, :provider_message_id],
             where: "provider_message_id IS NOT NULL",
             name: :channel_messages_provider_message_index
           )

    create index(:channel_messages, [:next_attempt_at],
             where: "status = 'queued'",
             name: :channel_messages_due_index
           )

    create index(:channel_messages, [:organization_id, :inserted_at])
    create index(:channel_messages, [:contact_id, :inserted_at])

    create constraint(:channel_messages, :channel_messages_check,
             check: """
             channel IN ('sms', 'viber', 'whatsapp') AND purpose IN ('service', 'marketing')
             AND status IN ('queued', 'sending', 'sent', 'delivered', 'failed', 'cancelled')
             AND source IN ('staff', 'automation', 'system')
             AND attempts >= 0 AND segments >= 1 AND estimated_cost_cents >= 0
             AND (cost_cents IS NULL OR cost_cents >= 0)
             """
           )

    create table(:channel_message_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :message_id, :binary_id, null: false
      add :kind, :string, null: false
      add :status, :string, null: false
      add :provider_status, :string, size: 60
      add :error_code, :string, size: 60
      add :detail, :string, size: 500
      add :event_key, :string, size: 160
      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE channel_message_events
    ADD CONSTRAINT channel_message_events_message_fkey
    FOREIGN KEY (message_id, organization_id)
    REFERENCES channel_messages (id, organization_id) ON DELETE CASCADE
    """)

    create index(:channel_message_events, [:message_id, :occurred_at])

    create unique_index(:channel_message_events, [:organization_id, :event_key],
             where: "event_key IS NOT NULL",
             name: :channel_message_events_key_index
           )

    create constraint(:channel_message_events, :channel_message_events_check,
             check: "kind IN ('attempt', 'receipt')"
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
  end

  def down do
    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))
  end
end
