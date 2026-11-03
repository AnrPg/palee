# ADR-349: Palee's SMS account by default, per-box cost, monthly budget cap, quiet hours
Date: 2026-10-31
Status: Accepted

## Context
Text messages cost money per message, unlike push. ANR (2026-10-31): the default is
Palee's own Brevo account, with each box's cost tracked and capped; a box may use its own
Brevo key instead. Messages at night annoy people and break Greek marketing practice.

## Decision
1. **`account_mode`** on the connection: `palee` (default) uses
   `config :palee, :channel_managed_accounts` (runtime: `BREVO_API_KEY` /
   `CHANNELS_BREVO_API_KEY`, sender `CHANNELS_BREVO_SMS_SENDER`, default `Palee`; the box may
   set its own sender name); `own` stores the box's API key encrypted (`EncryptedBinary`),
   never returned, logged, journaled or exported (`has_secret` only).
2. **Cost per box**: every message stores `estimated_cost_cents` (price list
   `CostPolicy.default_prices/0` per channel, purpose and destination country, times the
   SMS parts; replaceable by `config :palee, :channel_prices`) and, when the provider tells
   it, `cost_cents` (Brevo credits × `CHANNELS_BREVO_CREDIT_CENTS`). The month's spend is the
   sum over queued, sent, delivered and charged failed messages, on the box's clock.
3. **Monthly budget cap** `monthly_budget_cents` (default 20 €, 0 stops everything): a
   message whose estimate would pass the cap is refused with `channel_budget_exceeded`
   (automations fall through to their next channel). `GET …/channels/usage?month=YYYY-MM`.
4. **Quiet hours** on the box's clock (ADR-176/179), 21:00–09:00 by default, either may be
   switched off: a message created inside them waits (`hold_reason: quiet_hours`) until
   they end; an `urgent` service message goes at once.
5. **SMS parts**: GSM-7 160/153, UCS-2 70/67 (lower-case Greek is UCS-2, so a Greek SMS of
   71 characters is two parts). The preview shows parts and cost before sending.

## Rationale
Tracking cost per message (not per box invoice) keeps every billing option open: included
quota per plan, pass-through with a margin, or prepaid credit. The cap protects both the box
and Palee from a runaway automation.

## Alternatives Considered
- Only the box's own account: simpler for Palee, but a box would need a Brevo account before
  sending a single message.
- Charging at send time through the platform plan: needs ANR's billing decision first.

## Consequences
- **Open for ANR**: how boxes on Palee's account are charged (included SMS per plan,
  pass-through, prepaid), and the Greek price per Brevo credit.
- Concurrent sends may pass the cap by at most one message's estimate.

## Implementation Notes
Default prices (cents): SMS 7 per part (GR, CY), 9 elsewhere; Viber 2–3, WhatsApp 3
(service) / 9 (marketing) for when those channels come.

## Amendment (ADR-390, 2026-11-03)

ANR, v3.1 questions 1 and 2: no invented defaults. §3's 20 € cap is gone: the box types its own cap before a channel goes on (`monthly_budget_cents` required then; without one nothing is sent, `channel_budget_missing`). §4's 21:00–09:00 is gone: quiet hours start off and the box picks both times under «Προχωρημένα»; they hold only marketing messages, and service messages always go at once. Existing connections keep their values.
