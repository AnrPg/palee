# ADR-351: A narrow «send through channel» application API
Date: 2026-10-31
Status: Accepted

## Context
Automations (CP-C2, W2), staff messages and system notices need to send a text message
without knowing about providers, consent or budgets.

## Decision
1. `Palee.Application.Channels.SendThroughChannel.call(context, params)` with `user_id` or
   `lead_id`, `template_key`, `variables`, `purpose`, optional `channels` (preference),
   `urgent`, `idempotency_key` (required), `source` (`staff`, `automation`, `system`) and
   `source_ref`. It answers `{:ok, %{id, channel, status, release_at,
   estimated_cost_cents…}}` or `{:error, reason}`; `preview/2` runs the same checks without
   queuing. `{{box}}` and the box's time zone are filled in by the API.
2. Reasons a caller acts on: `channels_not_connected`, `channels_connection_invalid`,
   `channel_contact_missing`, `channel_consent_missing`, `channel_opted_out`,
   `channel_not_enabled`, `whatsapp_template_missing`, `channel_template_missing`,
   `channel_budget_exceeded`, `idempotency_key_reused`, `{:invalid_fields, …}`.
3. `Palee.Application.Channels.AutomationSmsChannel` fits W2's
   `Palee.Automations.Ports.Channel` (`channel/0`, `reachable?/1`, `deliver/1`): every
   refusal is `{:permanent, reason}` so the automation falls through to its next channel;
   provider outages are retried inside the Channels outbox. The integrator registers it as
   `config :palee, :automation_channels, %{"sms" => …}`.
4. Staff endpoints (`/api/org/:slug/admin/channels/…`): settings, check, usage, templates
   (`manage_settings`); contacts, consents, messages, preview, send, retry, cancel
   (`message_from_box`). Sending is rate limited (60/minute per staff member).

## Rationale
One entry point keeps consent, quiet hours and budget impossible to skip, and the
idempotency key makes automation retries safe.

## Alternatives Considered
Letting automations call the context directly: would spread the box name, time zone and
scheduling logic to every caller.

## Consequences
- A box in demo mode (ADR-184) sends nothing through these channels: `send` and `preview`
  answer `channels_demo_mode` (409) until the box is activated; it may still connect and
  test its provider (product owner, 2026-11-02).
Push stays first (CP-C3): callers choose when SMS is a fallback.

## Implementation Notes
The member endpoint `GET/PUT /api/org/:slug/me/channels` lets a member keep their own
number and consents.
