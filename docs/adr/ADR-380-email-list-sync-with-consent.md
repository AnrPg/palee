# ADR-380: Mailchimp/Brevo email-list sync, consent first
Date: 2026-10-31
Status: Accepted (v3.2, CP-F5)

## Context
Boxes send newsletters and offers from Mailchimp or Brevo and keep the list by hand, or export
everyone, consent or not. CP-F5 asks for an audience-sync adapter "with consent". W3 (ADR on
phone channels) keeps SMS/Viber/WhatsApp consent in `channel_consents`; it does not cover email
marketing, so this ADR owns that consent with the same columns.

## Decision
1. **Consent is the member's own.** `integration_marketing_consents` (one row per box and
   member): `granted_at`, `withdrawn_at`, `source`, `text_version`. Off by default; only the
   member changes it (`GET|PUT /api/org/:slug/me/marketing-consent`, Profile › «Ενημερώσεις με
   email»), never staff and never an import. Withdrawing keeps when consent was given, as proof
   (GDPR art. 7(1)). The consent text is versioned (`text_version`).
2. **One rule, in the domain.** `AudienceSyncPlan.plan/2`: subscribe exactly the active members
   with consent now; unsubscribe every synced member who withdrew, left the box or has no email.
   Adapters never decide who is sent.
3. **Data minimisation.** A contact is email and first name only. Palee remembers per member the
   SHA-256 of the address sent and the status (`audience_members`), not the address.
4. **Unsubscribe, never delete** in the provider: the provider must keep the address to honour
   the unsubscribe. Mailchimp: `PUT /3.0/lists/{list}/members/{md5(lower(email))}` with
   `status_if_new: subscribed` / `PATCH ... status: unsubscribed`; data centre from the key's
   suffix; basic auth. Brevo: `POST /v3/contacts` with `listIds` and `updateEnabled: true`;
   `POST /v3/contacts/lists/{id}/contacts/remove`; `api-key` header.
5. **Connection.** `audience_connections` (one per box): provider, list id, encrypted key (never
   returned), status, last sync and error. The provider is asked (`check/1`) before saving; a
   refused key during a sync stops it and marks the connection `invalid`.
6. **When.** After a consent change and «Συγχρονισμός τώρα» (a job per box, leased so runs never
   overlap), and hourly for boxes due (asked for, or a day since the last sync).
7. **Erasure.** Account deletion first unsubscribes the person from every box list they are
   subscribed to, while the address is still known (`AudienceSync.forget_person/1`), then the rows
   go with the account. GDPR export includes the consent and list status rows.

## Rationale
Making consent a precondition in the domain (not a filter in each adapter) means a new provider
cannot leak people who said no. Hash-only memory keeps Palee from building a second copy of the
mailing list.

## Alternatives Considered
- **Reuse W3's `channel_consents`**: its check constraint and API are phone channels; adding
  email there couples two workstreams' migrations. Same column semantics instead; can merge later.
- **Export a CSV for the box to import**: no withdrawal path, the classic GDPR failure.
- **Sync all members and rely on the provider's double opt-in**: still sends personal data to a
  processor without a basis.

## Consequences
- The box is the controller of its list; Palee is the processor sending what members agreed to.
  The box's privacy notice must name its provider (open question for the product owner).
- Disconnecting the list leaves the list as it is (the box owns it).
- Follow-up: provider webhooks for unsubscribes made in Mailchimp/Brevo (today a member who
  unsubscribes there stays unsubscribed there; Palee does not resubscribe them unless their hash or
  consent changes).

## Implementation Notes
- Port `Palee.Integrations.Ports.AudienceProvider` (`check/1`, `subscribe/2`, `unsubscribe/2`);
  adapters `MailchimpAudience`, `BrevoAudience`, `SandboxAudience` (dev/test only); Req options
  from `config :palee, :audience_http`.
- Settings: `GET|PUT|DELETE /admin/integrations/email-list`, `POST /admin/integrations/email-list/sync`.

## Amendment 2026-11-03: consent model and screens (W10 screen 3, option A)
- **Consent stays in its own table.** W3's channel consents (ADR-348..351, 368, 369, 390) are keyed by a
  phone contact (`channel_contacts.phone_e164` is required, and STOP withdraws by number). An email-only
  consent would need W3's table and every SMS path to change, so `integration_marketing_consents` keeps the
  same shape (person, purpose, granted/withdrawn, source, time) without sharing rows. One ledger for
  every consent (mockup option 3C) is left to ANR.
- **The member's switch lives in Box › Ειδοποιήσεις** («Ενημερώσεις με email από το {box}»), next to W3's
  SMS switches, and only when the box has connected a list; not under Προφίλ, because a box's own
  consents already live in Box.
- Settings › Συνδέσεις › Λίστα email connects Mailchimp or Brevo (service, key, list id; errors stay on
  their field), shows the last sync and «Συγχρονισμός τώρα», and reminds the box to name the service in
  its privacy notice. Subscriber counts are not shown: the API does not return them yet.
