# ADR-369: Palee's margin on Palee-managed messages, and the box's monthly charge
Date: 2026-11-01
Status: Accepted

## Context
ADR-349 tracked what each message costs a box on Palee's own provider account and left
open how Palee charges for it. Product owner decision (2026-11-01): the box sees and is
charged the provider's cost plus a Palee margin; the margin is a platform setting the
Palee team edits; messages sent on the box's own provider account carry no margin and no
Palee charge; billing will pick up a monthly charge later (no invoicing now).

## Decision
1. **Setting** `channel_platform_settings` (platform data, one row, no tenant):
   `margins_bps` per channel (`sms`, `email`, and `viber`, `whatsapp` for when they come),
   in basis points (2500 = 25 %), 0 until set, at most 100 000. Edited in the vendor
   console: `GET/PUT /api/platform/channel-margins` (vendors only, like the other
   `/api/platform` settings). A save sends only the channels it changes.
2. **Box price** `CostPolicy.price(provider_cents, margin_bps)` = provider price × (1 +
   margin), whole cents rounded up. When a message is queued on Palee's account
   (`account_mode: palee`) the margin of its channel is frozen on the row (`margin_bps`),
   with the provider estimate (`provider_cost_cents`); `estimated_cost_cents` is now the
   box price. On the box's own account `margin_bps` is 0 and the price is the provider's.
3. **What the box sees** (preview, send result, message list, usage) is the box price
   only. When the provider reports what it charged (`cost_cents`), the box sees that price
   with the message's margin. `provider_cost_cents` and `margin_bps` are never in a box
   response.
4. **Budget cap**: the monthly cap (ADR-349) compares the month's spend in box prices plus
   the new message's box price.
5. **Monthly charge (read model)**: `Channels.monthly_charge/3` /
   `Application.Channels.ChannelMargins.monthly_charge(organization_id, "YYYY-MM")` sums,
   per box and month on the box's clock, the messages sent on Palee's account that count
   (queued, sending, sent, delivered, and failed ones the provider charged):
   `charge_cents`, `provider_cost_cents`, `margin_cents`, `messages`, `by_channel`. The
   box's usage shows `palee_charge_cents`; the Palee team reads the full charge at
   `GET /api/platform/organizations/:id/channel-charges?month=YYYY-MM`. Own-account
   messages are not in it.

## Rationale
Freezing the margin on each message keeps a month's charge stable when the Palee team
changes the margin mid-month, and makes the charge a plain sum. Rounding up per message
means a margin never rounds to nothing on a 7-cent SMS. Keeping the provider's cost beside
the price lets the Palee team check the margin without showing it to boxes.

## Alternatives Considered
- A margin per plan or per box: more flexible, but the product owner asked for one
  platform margin; a per-plan override can be added to the setting later.
- Charging per invoice line at month end only: loses the per-message price the box sees
  in the preview and in the budget.

## Consequences
- Email has a margin setting but Palee-managed email has no per-message cost yet (the
  email outbox does not price mail), so nothing is charged for email until it does.
- Messages queued before this change have `margin_bps` 0 and `provider_cost_cents` null;
  their box price equals their old estimate.

## Implementation Notes
- Migration `20270503100000_channels_own_email_and_palee_margin.exs`: the setting table,
  `channel_messages.provider_cost_cents` and `margin_bps` (check `margin_bps >= 0`).
- `ChannelStore.spend/3` groups by channel and account mode and returns, besides the box
  total, `palee_charge`, `provider_total` and `palee_by_channel`.
