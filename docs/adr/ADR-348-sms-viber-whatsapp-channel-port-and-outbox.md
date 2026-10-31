# ADR-348: SMS, Viber and WhatsApp behind one MessagingChannel port, with an outbox
Date: 2026-10-31
Status: Accepted

## Context
CP-C3 (P1, v3.1): boxes want to reach members and leads outside the app, for the cases
push does not cover (the person has no app, an urgent cancellation). Competitors offer SMS
(Kilo 1,200/month), WhatsApp (PushPress) or both. In Greece Viber is more common than
WhatsApp. The product owner (ANR) decided on 2026-10-31: **SMS through Brevo** (the account
Palee already uses for transactional email), **no Viber for now**, WhatsApp only if cheap
(it is not: see below), Palee's own Brevo account by default with per-box cost tracking and
budget caps, and a box's own Brevo key as an option (ADR-349).

## Decision
1. **A new bounded context `Palee.Channels`** (tables `channel_*`, migration
   `20270503000000`), separate from in-app Μηνύματα (ADR-282) and from the platform's
   verification SMS port (`Application.Ports.SmsSender`, ADR-280), which stays as it is.
2. **Port `Channels.Ports.MessagingChannel`**: `send_message/2`, `check/1` («Δοκιμή
   σύνδεσης»), `parse_webhook/2` (verifies the provider's signature where it signs and
   reads receipts and inbound texts), `channels/0`. Errors are `:rejected` (not retried),
   `:unauthorized` (connection marked invalid), `:transient` (retried) and `:uncertain`
   (the call may have reached the provider: never sent again by itself, fails as
   `delivery_uncertain` so nobody gets it twice). Channels in the port: `sms`, `viber`,
   `whatsapp`.
3. **Adapters** (`config :palee, :channel_providers`): `sandbox` (no network; dev, tests,
   demo boxes; a number ending in `000` is refused, `999` meets an outage) and `brevo`
   (`POST /v3/transactionalSMS/sms` with `webUrl` per message, `GET /v3/account` for the
   check, webhook events `sent`, `delivered`, `soft_bounce`, `hard_bounce`, `rej`, `bl`,
   `replied`, `unsubscribed`). HTTP goes through `Infrastructure.Channels.Http` with
   `req_options` from config (Req.Test in tests), never retrying by itself.
4. **Outbox `channel_messages`**: one row per message, unique per box by
   `idempotency_key`, states `queued → sending → sent → delivered | failed`, plus
   `cancelled`. Workers claim due rows with `FOR UPDATE SKIP LOCKED` and spend one attempt
   per claim; transient errors back off 1, 5, 15, 60 minutes up to 5 attempts. Consent is
   checked again at send time (it may be withdrawn while a message waits). A missing or
   refused connection defers without spending attempts. `channel_message_events` is the
   insert-only log of attempts and receipts; receipts are deduplicated by the provider's
   event key, and arrive out of order safely (`delivered`/`failed` are final).
   `DeliverChannelMessagesJob` (queue `channels`, 2) runs right after a send and every two
   minutes for retries and messages held for quiet hours.
5. **Webhook** `POST /api/webhooks/channels/:organization_id/:token`: one URL per box. The
   token is an HMAC (`CHANNELS_WEBHOOK_KEY`, else the secret key base) of the box and a
   random salt on the connection, so the URL is rebuilt for every message (Brevo's
   `webUrl`) and can be changed by drawing a new salt (`rotate_webhook`). Brevo does not
   sign its webhooks, so the token is the authentication, and a receipt must name a
   message of that box. The raw body is kept (`CacheRawBody`) for providers that sign it.
6. **Phone numbers** are stored in E.164 (`Domain.PhoneNumber`): national forms of the box's
   country (`default_country`, GR by default) are accepted; Greek and Cypriot numbers must
   be mobiles. Staff see them masked.

## Rationale
The fiscal outbox (ADR-243) already proved the shape: idempotent rows, row-locked claims, an
attempt log, a port per authority and a sandbox. Keeping provider details behind the port
lets ANR change provider, or add Viber/WhatsApp, without touching the domain.

## Alternatives Considered
Provider research, October 2026 (prices are list prices; Greece unless noted):

| Provider | Channels | Price seen | Notes |
|---|---|---|---|
| **Brevo** (chosen by ANR) | SMS (transactional and marketing), WhatsApp (templates via Brevo) | prepaid SMS credits per country; Greek rate not published, see the pay-as-you-go calculator | Palee already has the account and API key; delivery events by `webUrl`; no webhook signature. https://developers.brevo.com/docs/transactional-webhooks |
| Twilio | SMS, WhatsApp | SMS $0.0657/segment (alphanumeric sender) https://www.twilio.com/en-us/sms/pricing/gr ; WhatsApp = Meta fee + Twilio fee | Signed webhooks (HMAC-SHA1). No Viber. |
| Infobip | SMS, Viber Business Messages (official partner), WhatsApp | Viber/SMS by calculator https://www.infobip.com/viber-business/pricing ; SMS ~ $0.10 (third-party, 2025) | One account for all three; Viber needs a monthly minimum commitment. |
| Vonage | SMS, WhatsApp, Viber | not published for GR (Pricing API) | |
| Routee (Greek, AMD Telecom) | SMS, Viber | not published; Viber billed transactional/promotional https://docs.routee.net/docs/viber-messaging | |
| Yuboto, Modulus, Voiceland (Greek) | SMS, Viber | Modulus 0.031 €/SMS at volume and 200 €/month Viber minimum https://www.modulus.gr/pricing/mmp-pricing ; Voiceland 500 SMS 25 € https://voiceland.gr/en/business-messaging | Local routes; no developer-first APIs. |
| Viber via resellers | Viber | SMSBAT GR: 0.0104 € transactional, 0.0219 € promotional, 175 €/month minimum https://smsbat.com/help/billing/viber-pricing/ ; Messaggio from 0.0262 € https://messaggio.com/messaging/greece | Viber's monthly minimum makes it costly for a single box. |
| Meta WhatsApp Cloud API | WhatsApp | per message since 2025-07: GR ~ $0.086 marketing, ~ $0.021 utility (third-party calculators; Meta's official card lists GR under "Rest of Central & Eastern Europe") https://developers.facebook.com/docs/whatsapp/pricing | Needs a Meta Business account per box and pre-approved templates. |

Market benchmarks: Plivo $0.0585/SMS to COSMOTE https://www.plivo.com/sms/pricing/gr/ ;
BudgetSMS wholesale via Yuboto 0.047 € https://www.budgetsms.net/sms-gateway-pricing/gr/greece/ .

Twilio and Infobip adapters were written first (commit history of `v31/channels`) and then
removed when ANR chose Brevo; they can come back behind the same port. WhatsApp through
Brevo needs templates approved in Brevo's console and contact attributes for variables, so
it is not "cheap to add" today: listed as later.

## Consequences
- SMS from the box works with Palee's Brevo account once `BREVO_API_KEY` (or
  `CHANNELS_BREVO_API_KEY`) is set; `CHANNELS_BREVO_CREDIT_CENTS` turns Brevo credits into
  cents (else the outbox keeps its estimate, ADR-349).
- An alphanumeric SMS sender cannot receive replies, so STOP by SMS reply only works from a
  numeric sender; Brevo's own `unsubscribed` events are honoured (ADR-350).
- No screens yet: mockups first (`v31-mockups/w3-channels.html`).

## Implementation Notes
- `channel_connections` is one row per box; the provider list in its check constraint is
  `sandbox`, `brevo` (a later migration widens it for a new provider).
- Account deletion (ADR-211) deletes the person's contact, consents and messages in each
  box they are an active member of; GDPR export (ADR-267) includes them under `messages`.
- Tenant purge: context `channels`, purge order 68, secrets excluded from exports.
