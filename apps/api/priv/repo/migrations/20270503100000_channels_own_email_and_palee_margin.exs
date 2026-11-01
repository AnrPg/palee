defmodule Palee.Repo.Migrations.ChannelsOwnEmailAndPaleeMargin do
  @moduledoc """
  ADR-368: a box's own email provider over SMTP; ADR-369: Palee's margin on
  the messages it sends for a box.

    * `channel_email_connections` – one per organization (tenant table,
      forced RLS): the SMTP host, port, TLS mode, user name, the password
      encrypted with `DataCipher` (never returned, logged or exported), the
      sender and reply-to, whether it is switched on and the last check;
    * `channel_platform_settings` – the installation's one row (platform
      data, no tenant): Palee's margin in basis points per channel, edited
      by the Palee team;
    * `channel_messages.provider_cost_cents` / `margin_bps` – what the
      provider is expected to charge and the margin applied when the message
      was queued; `estimated_cost_cents` is now the box's price;
    * `email_messages.sent_via` – `palee` (Palee's mailer) or `own` (the
      box's SMTP), so Palee's daily email budget counts only its own mail.
  """

  use Ecto.Migration

  def up do
    create table(:channel_email_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :host, :string, size: 253, null: false
      add :port, :integer, null: false
      add :tls_mode, :string, size: 10, null: false, default: "starttls"
      add :username, :string, size: 254, null: false
      add :secret, :binary, null: false
      add :from_address, :string, size: 254, null: false
      add :from_name, :string, size: 120
      add :reply_to, :string, size: 254
      add :enabled, :boolean, null: false, default: true
      add :status, :string, size: 10, null: false, default: "unchecked"
      add :error_code, :string, size: 60
      add :checked_at, :utc_datetime_usec
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:channel_email_connections, [:organization_id])

    create constraint(:channel_email_connections, :channel_email_connections_check,
             check: """
             tls_mode IN ('starttls', 'tls')
             AND port IN (25, 465, 587, 2525)
             AND status IN ('unchecked', 'active', 'invalid')
             """
           )

    execute("""
    CREATE TRIGGER channel_email_connections_apply_tenant_context
    BEFORE INSERT OR UPDATE ON channel_email_connections
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY channel_email_connections_tenant_policy ON channel_email_connections
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE channel_email_connections ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE channel_email_connections FORCE ROW LEVEL SECURITY")

    create table(:channel_platform_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :singleton, :boolean, null: false, default: true
      add :margins_bps, :map, null: false, default: %{}
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:channel_platform_settings, [:singleton])

    create constraint(:channel_platform_settings, :channel_platform_settings_singleton_check,
             check: "singleton"
           )

    alter table(:channel_messages) do
      add :provider_cost_cents, :integer
      add :margin_bps, :integer, null: false, default: 0
    end

    create constraint(:channel_messages, :channel_messages_margin_check,
             check:
               "margin_bps >= 0 AND (provider_cost_cents IS NULL OR provider_cost_cents >= 0)"
           )

    alter table(:email_messages) do
      add :sent_via, :string, size: 10
    end

    create constraint(:email_messages, :email_messages_sent_via_check,
             check: "sent_via IS NULL OR sent_via IN ('palee', 'own')"
           )
  end

  def down do
    drop constraint(:email_messages, :email_messages_sent_via_check)

    alter table(:email_messages) do
      remove :sent_via
    end

    drop constraint(:channel_messages, :channel_messages_margin_check)

    alter table(:channel_messages) do
      remove :provider_cost_cents
      remove :margin_bps
    end

    drop table(:channel_platform_settings)
    drop table(:channel_email_connections)
  end
end
