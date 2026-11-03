defmodule Palee.Repo.Migrations.SmsCapTypedAndUnsubscribeLink do
  @moduledoc """
  ADR-390 (product owner, 2026-11-03):

    * `channel_connections.monthly_budget_cents` loses its invented 20 €
      default and may be empty: the box types its own cap when it turns SMS
      on, and nothing is sent while there is none. Existing rows keep their
      value.
    * `channel_consents.source` gains `unsubscribe_link`: a marketing SMS
      carries a short link that withdraws that consent.
    * `palee_channel_contact_organization(uuid)` finds the box of a contact
      for that public link (SECURITY DEFINER, `search_path` only); the link's
      signature is checked before it is called.
  """

  use Ecto.Migration

  def up do
    execute("ALTER TABLE channel_connections ALTER COLUMN monthly_budget_cents DROP DEFAULT")
    execute("ALTER TABLE channel_connections ALTER COLUMN monthly_budget_cents DROP NOT NULL")

    replace_consent_check(~w(person staff form import stop_keyword unsubscribe_link))

    execute("""
    CREATE FUNCTION palee_channel_contact_organization(contact uuid)
    RETURNS uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT c.organization_id FROM public.channel_contacts c WHERE c.id = contact
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_channel_contact_organization(uuid)")

    execute("""
    UPDATE channel_consents SET source = 'person' WHERE source = 'unsubscribe_link'
    """)

    replace_consent_check(~w(person staff form import stop_keyword))

    execute(
      "UPDATE channel_connections SET monthly_budget_cents = 0 WHERE monthly_budget_cents IS NULL"
    )

    execute("ALTER TABLE channel_connections ALTER COLUMN monthly_budget_cents SET NOT NULL")
    execute("ALTER TABLE channel_connections ALTER COLUMN monthly_budget_cents SET DEFAULT 2000")
  end

  defp replace_consent_check(sources) do
    list = Enum.map_join(sources, ", ", &"'#{&1}'")

    execute("ALTER TABLE channel_consents DROP CONSTRAINT channel_consents_check")

    create constraint(:channel_consents, :channel_consents_check,
             check: """
             channel IN ('sms', 'viber', 'whatsapp') AND purpose IN ('service', 'marketing')
             AND source IN (#{list})
             """
           )
  end
end
