defmodule Palee.Repo.Migrations.SmsOwnVendors do
  @moduledoc """
  ADR-396 (product owner, 2026-11-01): a box, solo coach or event organiser
  may bring its own SMS vendor. Besides Brevo, `channel_connections.provider`
  now accepts `twilio`, `vonage`, `infobip`, `yuboto` and `apifon`.

    * `webhook_secret` (encrypted at rest like `secret`, never returned,
      logged or exported): the vendor's own key for signing its delivery
      reports where it differs from the API secret (Vonage's signature
      secret). Optional.
    * `sms_sender` grows to 40 characters: a Twilio Messaging Service SID
      (`MG` and 32 hex digits) is a sender too.
  """

  use Ecto.Migration

  @providers ~w(sandbox brevo twilio vonage infobip yuboto apifon)

  def up do
    alter table(:channel_connections) do
      add :webhook_secret, :binary
      modify :sms_sender, :string, size: 40, from: {:string, size: 20}
    end

    replace_connection_check(@providers)
  end

  def down do
    execute("""
    UPDATE channel_connections
       SET provider = 'brevo', account_mode = 'palee', secret = NULL, account_id = NULL,
           base_url = NULL, channels = '{}'
     WHERE provider NOT IN ('sandbox', 'brevo')
    """)

    execute("UPDATE channel_connections SET sms_sender = NULL WHERE length(sms_sender) > 20")

    replace_connection_check(~w(sandbox brevo))

    alter table(:channel_connections) do
      remove :webhook_secret
      modify :sms_sender, :string, size: 20, from: {:string, size: 40}
    end
  end

  defp replace_connection_check(providers) do
    list = Enum.map_join(providers, ", ", &"'#{&1}'")

    execute("ALTER TABLE channel_connections DROP CONSTRAINT channel_connections_check")

    create constraint(:channel_connections, :channel_connections_check,
             check: """
             provider IN (#{list})
             AND account_mode IN ('own', 'palee')
             AND status IN ('active', 'invalid')
             AND channels <@ ARRAY['sms', 'viber', 'whatsapp']::varchar[]
             AND (monthly_budget_cents IS NULL OR monthly_budget_cents >= 0)
             AND (quiet_start_minute IS NULL OR quiet_start_minute BETWEEN 0 AND 1439)
             AND (quiet_end_minute IS NULL OR quiet_end_minute BETWEEN 0 AND 1439)
             AND (provider = 'sandbox' OR account_mode = 'palee' OR secret IS NOT NULL)
             """
           )
  end
end
