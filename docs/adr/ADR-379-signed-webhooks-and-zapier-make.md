# ADR-379: Signed webhooks with retries, and the Zapier/Make integration
Date: 2026-10-31
Status: Accepted (v3.2, CP-F5)

## Context
Integrations need to hear about changes (a new booking, a payment) without polling. CP-F5 asks
for signed webhooks with timestamps, retries with backoff, a delivery log and replay, and a
description of a Zapier/Make integration.

## Decision
1. **Events are thin.** `Palee.Integrations.Domain.PublicEvents` maps domain events (ADR-144) to
   `member.activated`, `booking.created`, `booking.cancelled`, `class.cancelled`,
   `attendance.recorded`, `payment.recorded` (+ `ping`). The envelope is `{id, type, api_version
   "2026-11-01", created_at, box_id, data}` and `data` holds ids and plain facts only (no names,
   emails, notes). A receiver reads more through the API with its own scoped key, so a leaked
   webhook URL gives away nothing personal (GDPR art. 5(1)(c)).
2. **Outbox.** `Palee.Application.Integrations.WebhookEvents` (a domain event handler) inserts one
   `webhook_deliveries` row per subscribed endpoint, with the same event id for all. A job
   (`DeliverWebhooksJob`, every minute, queue `integrations`) leases due rows with
   `FOR UPDATE SKIP LOCKED` (lease 120 s, batch 25) and posts them.
3. **Signature.** `Palee-Signature: t=<unix>,v1=<hex HMAC-SHA256(secret, "t.body")>`; receivers
   should reject `t` older than 5 minutes. Per-endpoint secret `whsec_…` (encrypted at rest,
   shown once). **Secret rotation** signs with both secrets (two `v1=` values) for 24 hours.
4. **Retries.** 2xx = delivered. Otherwise retried after 1 m, 5 m, 30 m, 2 h, 6 h, 12 h, 24 h,
   24 h (9 attempts over ~3 days), then `failed`. `410 Gone` fails at once and turns the endpoint
   off (a REST-hook unsubscribe). 20 deliveries in a row that failed for good turn the endpoint off
   (`disabled_reason`). 10 s timeout, no redirects.
5. **Delivery log and replay.** `webhook_delivery_attempts` keeps every attempt (status, error,
   500-byte response excerpt, duration). Settings show the log per endpoint and resend any
   delivery (a new delivery with the same event id, `replay_of_id`). «Δοκιμή» sends `ping`.
6. **Endpoint safety.** `https` only; addresses that resolve to private, loopback, link-local or
   metadata ranges are refused when saved and again before each send (DNS check in the transport,
   SSRF). Up to 20 endpoints per box.
7. **REST hooks for Zapier and Make.** `POST /api/public/v1/webhook-subscriptions` (scope
   `webhooks:write`, plus each event's read scope) and `DELETE .../{id}` (only by the key that made
   it). Subscriptions belong to the key; revoking the key removes them.

## Zapier/Make mapping
| Zapier/Make | Palee |
|---|---|
| Authentication (API key, "Test") | Bearer key; test = `GET /me` (`key.describe`: box, key name, scopes) |
| Trigger "New member" | REST hook `member.activated`; perform-list sample `GET /members?limit=3` |
| Trigger "New booking" / "Booking cancelled" | `booking.created` / `booking.cancelled`; sample `GET /classes/{id}/bookings` |
| Trigger "Class cancelled" | `class.cancelled`; sample `GET /classes?from&to` |
| Trigger "Member attended" | `attendance.recorded` |
| Trigger "Payment recorded" | `payment.recorded`; sample `GET /payments` |
| Action "Invite member" | `POST /members/invitations` |
| Action "Book member into class" | `POST /bookings` (send `Idempotency-Key`: Zapier retries) |
| Action "Cancel booking" | `DELETE /bookings/{id}` |
| Action "Add class" | `POST /classes` |
| Action "Assign package" | `POST /members/{member_id}/packages` |
| Search "Find member" / "Find class" | `GET /members/{id}`, `GET /classes?from&to` |
| Hydration of thin events | each trigger's perform step calls `GET /members/{id}` etc. |

## What to submit to Zapier (and Make)
1. A Zapier Platform CLI app (`zapier init`, API-key auth with a `GET /me` test, the triggers as
   REST hooks with `performSubscribe`/`performUnsubscribe` to the endpoints above and a
   `performList` fallback, the actions above), kept in its own repo.
2. A public help article (Greek and English) on making a key, scopes and the triggers.
3. A test account (a sandbox box with demo data) and a test key for Zapier's reviewers.
4. Branding: app name «Palee», 256×256 logo, short and long description, category "Fitness".
5. Terms of service and privacy policy URLs (`/terms`, `/privacy`) and a support email.
6. Zapier's integration requirements: at least one trigger and one action working, HTTPS only,
   meaningful error messages (problem details `title`), no polling triggers without dedupe ids
   (events carry `id`).
7. Zapier lists a newly published integration as beta first; when it leaves beta is set by
   Zapier's current partner terms (to check at submission time, not assumed here).
Make: a Custom App built from the same OpenAPI document (connection = API key, webhooks = the REST
hooks above), then submitted for review as a public app.

## Rationale
Thin events plus API reads keep personal data out of third-party logs and make the API the one
place where scopes apply. An outbox with leases gives at-least-once delivery without a separate
queue service, the pattern used elsewhere (ADR-212 email outbox).

## Alternatives Considered
- **Fat events with names and emails**: convenient for receivers, but every endpoint would need
  the read scope's protection and the data would sit in Zapier's task history.
- **Polling-only triggers**: simpler but slow and expensive at Zapier's 1–15-minute intervals.
- **A hosted webhook service (Svix)**: another sub-processor holding member events; the volume
  does not justify it.

## Consequences
- Receivers must be idempotent by event `id` (at-least-once).
- The handler list in `config :palee, :domain_event_handlers` gains `WebhookEvents` for six events.
- Follow-up: per-event filters (branch), payload versions beyond `2026-11-01`, a status page of
  endpoint health for owners.

## Implementation Notes
- Tables `webhook_endpoints`, `webhook_deliveries`, `webhook_delivery_attempts`; SECURITY DEFINER
  `palee_webhook_due_organizations(timestamp)` lets the sweeper find boxes with due rows.
- Settings: `/admin/integrations/webhooks[/:id[/test|/rotate-secret|/deliveries]]`,
  `/admin/integrations/deliveries/:id[/replay]`.

## Amendment 2026-11-03: screens (W10 screen 2, option A with C's health)
- The list shows each webhook with a health badge (OK, failing, off). Each opens its own page,
  `/admin/settings/webhooks/:id`: events, on/off, test, new secret, delete, and the delivery log
  (all, retrying, failed) with each delivery's payload, attempts and «Ξανά».
- The signing secret is shown once, on creation and on rotation.

## Amendment 2026-11-03 (b): telling the owners when Palee turns a webhook off
- When a delivery run turns an endpoint off (`too_many_failures`, `gone`, `blocked_address`), each person who
  manages settings gets a bell notification `webhook_disabled` (category `staff`, link to the webhook's page)
  and an email `webhook_disabled` (category `account`) saying why and what to do. Both are keyed by the
  endpoint and the moment it was turned off, so a retried job never sends twice. A box turning its own
  webhook off hears nothing.
- `Integrations.deliver/3` now also returns the endpoints it turned off; the application layer
  (`ConnectionNotices`) sends the notices, so the context stays free of Notifications and Email.
- Migration `20270604000000_open_platform_follow_ups` adds the notification type.
- The Zapier and Make app submission is left for later.
