# ADR-368: The box's own email provider over SMTP («Δικός μου πάροχος email»)
Date: 2026-11-01
Status: Accepted

## Context
Product owner decision (2026-11-01): Palee sends a box's SMS and email by default
(`account_mode: palee`, ADR-349). Bringing your own provider is the advanced option. For
SMS that option exists (a box's own Brevo key, ADR-349). For email it did not: every
email, the box's own included, left from Palee's address through Palee's Brevo SMTP
account (ADR-203) and counted against Palee's daily budget of about 300 mails.

A box that wants its automations and receipts to come from its own domain, through the
provider it already pays (Google Workspace, Microsoft 365, Mailgun, Brevo, Postmark, a
Greek host…), needs to connect it. Every email provider speaks SMTP, so one connection
shape covers them all without an adapter per vendor.

## Decision
1. **Connection** `channel_email_connections` (Channels context, one per organization,
   tenant table with forced RLS): `host`, `port` (25, 465, 587 or 2525), `tls_mode`
   (`starttls` or `tls`; plain-text SMTP is never accepted), `username`, `secret` (the
   password, `EncryptedBinary` like the channel API key and the payment credentials),
   `from_address`, `from_name`, `reply_to`, `enabled`, `status` (`unchecked`, `active`,
   `invalid`), `error_code`, `checked_at`. The password is never returned (`has_secret`
   only), logged, journaled or exported (the column is `secret`, already excluded by the
   Channels tenant-data policy). No person data: the connection is the box's.
2. **«Δοκιμή σύνδεσης»** connects, upgrades to TLS (verified: TLS 1.2+, the CA store and
   the host name, `Palee.Mailer.tls_options/1`), logs in and quits. Nothing is sent. A
   change to the host, port, TLS mode, user name or password puts the connection back to
   `unchecked`; renaming the sender or switching it on and off keeps the result.
3. **Routing.** Email templates declare their origin (`use Palee.Email.Template,
   origin: :box`; `:platform` by default). The box's own messages are `box_automation`
   (W2's email channel, ADR-346), `fiscal_document`, `corporate_invoice_issued` and
   `corporate_invoice_reminder`. The outbox worker (`DeliverEmail`) sends a box-origin
   email of an organization through `Palee.Email.Ports.BoxSender`
   (`config :palee, :email_box_sender`, `Application.Channels.BoxEmailSender`), which uses
   the box's SMTP when the connection is `enabled` and `active`. Otherwise — no
   connection, switched off, unchecked, or the provider refused the password just now
   (the connection becomes `invalid`, `credentials_rejected`) — the same attempt goes
   through Palee's mailer as before. Platform mail (verification, password reset, security
   notices, invitations to Palee accounts, status page, share links) always goes through
   Palee's mailer.
4. **Outbox bookkeeping.** `email_messages.sent_via` records `palee` or `own`. Mail sent
   through the box's SMTP skips Palee's daily budget and does not count towards it.
   Suppression, unsubscribe (ADR-212), the demo gate (ADR-184), throttles, the
   Message-ID chosen at enqueue and retries are unchanged. A 5xx from the box's provider
   fails the email for good; anything else is retried with the outbox's backoff.
5. **Port** `Channels.Ports.EmailTransport` (`check/1`, `deliver/2`) with adapters
   `SmtpEmailTransport` (production: `Swoosh.Adapters.SMTP` with the connection's settings
   per message) and `SandboxEmailTransport` (dev and test: nothing leaves; `wrong-password`
   is refused, a `down.` host is unreachable, a `private.` host is not allowed, a
   recipient at `@reject.test` is refused for good) via `config :palee,
   :channel_email_transport`.
6. **No SSRF.** The host must be a public name (not an address, `localhost` or an
   internal or reserved domain), and the adapter resolves it and refuses to connect if any
   address is loopback, private, link-local, shared or reserved. Only mail ports are
   allowed. Each SMTP call runs in a task with a deadline (30 s for the check, 90 s for a
   send), because gen_smtp waits up to 20 minutes for a reply.
7. **DNS guide data.** `GET …/channels/email` returns `dns_guidance`: the sender domain
   and the reminders the future guide screen shows (`email_dns.spf`, `email_dns.dkim`,
   `email_dns.dmarc`, `email_dns.same_domain`), with the record type and host to fill in.
   The texts belong to the screen (i18n keys), not to the API.
8. **API** (`manage_settings`): `GET/PUT/DELETE /api/org/:slug/admin/channels/email` and
   `POST …/channels/email/check`. Error `email_connection_missing` (404).

## Rationale
SMTP is the one protocol every provider supports, so the box chooses any vendor and Palee
maintains one adapter. Routing on the template's origin keeps the rule in one place: what
the box says to its people may come from the box, what Palee says about accounts and
security always comes from Palee, so a misconfigured box can never lock someone out of a
password reset. Falling back to Palee keeps the box's mail flowing while it fixes its
settings.

## Alternatives Considered
- **Per-vendor API adapters (Brevo, Mailgun, Postmark…)**: richer events, but one adapter
  and one secret format per vendor; SMTP covers all of them now and API adapters can come
  later behind the same port.
- **Hold the box's email when its provider fails**: no mail lost to the wrong sender, but
  members miss receipts and reminders; rejected for the default (open question below).
- **Send with the box's From through Palee's provider**: breaks SPF/DMARC alignment for
  the box's domain without delegating DNS to Palee.

## Consequences
- Delivery events (bounces, complaints) of mail sent through the box's provider do not
  reach Palee's Brevo webhook; suppression only knows Palee's own events.
- DNS rebinding between the check and the connect is not prevented (the address is
  checked, then gen_smtp resolves again); the port allowlist limits the impact.
- No new screen: the settings card and the DNS guide wait for approved mockups.

## Implementation Notes
- Migration `20270503100000_channels_own_email_and_palee_margin.exs` (shared with
  ADR-369).
- Tenancy audit: `channel_email_connections` is a ready tenant table; the Channels
  tenant-data policy lists it (purge with the tenant, `secret` excluded from exports).
- `Palee.Email.MessageStore.count_sent_since/1` ignores `sent_via: own`.
