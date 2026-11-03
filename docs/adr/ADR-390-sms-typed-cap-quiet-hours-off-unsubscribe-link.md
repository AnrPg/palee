# ADR-390: SMS: the box types its own cap, quiet hours start off, a short unsubscribe link
Date: 2026-11-03
Status: Accepted

## Context
The product owner (ANR) answered the v3.1 questions on 2026-11-03
(questions 1, 2 and 4) by accepting the proposals. Three earlier choices
broke the rule "no invented defaults" or did not work in practice:
- ADR-349 §3 gave every box a 20 € monthly SMS cap nobody chose.
- ADR-349 §4 gave every box quiet hours 21:00–09:00 nobody chose, and held
  service messages (a class cancelled tonight) unless the caller marked them
  urgent.
- ADR-350 §3 ended marketing SMS with «Για διακοπή απάντησε STOP.», but the
  sender is the box's name («BoxKypseli»), and an alphanumeric sender cannot
  receive replies, so the instruction could not work.

## Decision
1. **Monthly cap typed by the box.** `channel_connections.monthly_budget_cents`
   has no default and may be empty (migration `20270514000000`; existing rows
   keep their value). Saving a connection with any channel on and no cap
   answers `422 validation_failed` with `monthly_budget_cents: ["required"]`,
   shown under the field (ADR-214). A connection without a cap sends nothing:
   `send` and `preview` answer `channel_budget_missing` (409), which «Ενημέρωση
   συμμετεχόντων» reports once as `sms_blocked`. The web asks for the cap
   (typed, no suggested amount) when the switch is first turned on, and the
   box's own Brevo key no longer switches SMS on by itself.
2. **Quiet hours start off.** A new connection has none (`QuietHours.defaults/0`
   is gone). The box opens them under «Προχωρημένα» and picks both times;
   nothing is suggested. They hold only **marketing** messages: service
   messages (class cancelled, booking reminder, payment due, event reminder)
   always go at once, urgent or not (`QuietHours.applies?/1`).
3. **Unsubscribe link instead of STOP.** A marketing SMS ends with
   « Διακοπή: palee.app/u/<token>» (one word per language, then the link on
   the app host without `https://`). Service messages carry no link. The
   token is the contact's id and the first 6 bytes of an HMAC-SHA256 with a
   key derived from `CHANNELS_WEBHOOK_KEY` for this purpose, url-safe base64
   (30 characters); only its one spelling is accepted, and it does not
   expire. `GET /api/public/channels/unsubscribe/:token` names the box and
   says whether offers by SMS are already off (it changes nothing, so a
   link preview unsubscribes nobody); `POST` withdraws that contact's `sms` /
   `marketing` consent with the new source `unsubscribe_link` (recorded on
   the consent like every change, ADR-350), once. The box is found from the
   contact by `palee_channel_contact_organization(uuid)` (SECURITY DEFINER,
   `search_path` only), called only after the signature is checked; the
   contact is then read in that box's own tenant session. The public page
   `/u/:token` shows the box's name, says updates keep coming and has one
   button, «Διακοπή». Never the number.
4. A STOP reply still works from a numeric sender and Brevo's own
   `unsubscribed` event (ADR-350 §3 unchanged).

## Rationale
A cap or quiet hours the box never chose are Palee's choices made in the
box's name. Holding a cancelled class's SMS until 09:00 defeats the point of
the message. A link works from any sender, costs no reply SMS and needs no
inbound number.

## Alternatives Considered
- A numeric sender so STOP replies work: the person sees a number instead
  of the box's name; rejected by ANR.
- A random code stored per contact: needs a column and a unique global
  lookup; the signed id needs neither and cannot be enumerated.
- Withdrawing on opening the link: phones fetch links for previews.
- Keeping `urgent` as the only way past quiet hours: every caller would have
  to remember it for service messages.

## Consequences
- Supersedes ADR-349 §3 (the 20 € default) and §4 (21:00–09:00 by default,
  urgent-only bypass), and the STOP sentence of ADR-350 §3.
- The link adds about 45 characters to a marketing SMS (in Greek, often one
  more part); the preview shows parts and cost before sending as before.
- `urgent` remains on the message as a label; it no longer changes when a
  message leaves.
- A box that connected before this change keeps its 20 € cap and its quiet
  hours; nothing is migrated.

## Implementation Notes
- `Channels.Domain.UnsubscribeLink` (pure), `Channels.Unsubscribe`,
  `Application.Channels.SmsUnsubscribe`, `PublicSmsUnsubscribeController`
  (rate limited with the email unsubscribe bucket), `ChannelStore.contact_organization/1`.
- Web: `SmsConnectionSettings` (`BudgetField`, `QuietHoursRow` under
  «Προχωρημένα»), `sms.ts` (`budgetCents`, `budgetInput`, `quietHoursReady`),
  `app/u/[token]`, `SmsUnsubscribePage`.

## Amendment (2026-11-03, ANR)
Quiet hours start **on** for a new connection, 21:00–09:00 (`QuietHours.initial/0`), on each
recipient's own clock: the zone their device last reported (ADR-179), else the box's for leads and
people with no known zone (`SendThroughChannel.recipient_time_zone/1` passed in `env`).
The box changes or closes them under «Προχωρημένα». They still hold only marketing messages; service
messages always go at once.
