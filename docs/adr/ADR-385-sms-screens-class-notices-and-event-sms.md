# ADR-385: SMS screens: class notices (app first), the event SMS switch and the cost breakdown
Date: 2026-11-02
Status: Accepted

## Context
The product owner (ANR) picked the W3 SMS mockups on 2026-11-02 (`w3-channels.html`). The
API of ADR-348..351 and ADR-368/369 covers connection, consent, sending and cost, but three
picked screens need facts it did not give:
- Screen 3 A (the month bar «ποιος τα ξόδεψε»): spend by who sent it, and how many messages
  arrived or failed. `usage` only grouped by channel.
- Screen 4 Γ («Ενημέρωση συμμετεχόντων» from a class): the app first, SMS only for the
  participants the app cannot reach, with counts and cost before sending. Sending existed
  only one person at a time.
- Screen 6 B and C (organisers): «12 από 40 θα πάρουν SMS», the event's SMS cost and a
  per-event SMS switch; and screen 5 A needs to know whether «Θα έρθω» should ask for SMS.

## Decision
1. **Usage** (`GET …/admin/channels/usage`, and the `usage` in settings) adds `segments`,
   `by_source` (`automation`, `staff`, `system`: cents and count, charged as the month's spend)
   and `by_status` (every message of the month by state, charged or not).
2. **Class notices** (`Application.Channels.ClassNotices`):
   `POST /api/org/:slug/admin/channels/class-notices/preview` and `…/class-notices`
   (`message_from_box`, branch scope through `ClassLocation.authorize_class`). Body:
   `slot_id`, `kind` (`cancelled`, `changed`, `free`), `text` (required for `free`, ≤ 300),
   `urgent` (`free` only; the other two are always urgent), `locale`, and `idempotency_key`
   when sending. Participants are the members with an approved or pending booking. A
   participant with a push device (web push subscription or phone token,
   `Notifications.reachable_in_app?/1`) gets the notice in the app (`box_message`, free);
   the rest go through `SendThroughChannel` with `channels: ["sms"]`, purpose `service`,
   templates `class_cancelled`, `class_changed` or `box_message`, `source: staff`,
   `source_ref: class:<id>`, one idempotency key per person; whoever has neither has no
   way. The answer counts `in_app`, `sms`, `unreachable` (with reasons), the SMS cost,
   the budget, the first SMS as a sample, and `sms_blocked` when the box itself cannot send
   (`channels_demo_mode`, `channels_not_connected`, `channel_budget_exceeded`…).
3. **Event SMS switch**: `community_events.sms_enabled` (migration `20270510000000`, default
   true so nothing changes for existing events), editable with the event. Off: the reminder
   and changes go by push only. Every event carries `sms_enabled` and `sms_offered`
   (switch on, and the organisation has an active connection with SMS on and is not in
   demo mode); «Θα έρθω» asks for SMS only when `sms_offered`.
4. **Event SMS summary** `GET /api/me/events/:id/sms` (whoever runs events there): `enabled`,
   `connected`, `going`, `recipients` (going and agreed to SMS with the organisation),
   `spent_cents` (messages with `source_ref: event:<id>`), `per_message_cents` (one part to
   the organisation's country, margin included on Palee's account) and `currency`.

## Rationale
The class notice needs the app/SMS split on the server: only the server knows who has a
push device, and the per-person consent and cost checks must be the ones sending uses. The
event switch is a column on the event because it travels with the event (series edits,
co-hosts) and the reminder job already loads the event.

## Alternatives Considered
- Counting by source in the browser from the message list: wrong past 200 messages a month.
- Sending the class notice as one SMS per person from the browser: no app-first split, and a
  half-sent notice when the tab closes.
- A per-event switch in the organiser's settings (a list of event ids): drifts from the event.

## Consequences
- The class notice in the app is a `box_message` notification in the staff member's
  language (the SMS uses each person's language).
- Asking for SMS once after a booking (screen 2 B) needs no API: the member's `me/channels`
  shows whether they already answered with a consent; a «no» without a number is kept per
  device in the browser. A server-side «asked» record is an open question.
- `spent_on/2` reads at most one page (200) of an event's messages.

## Implementation Notes
- Web: Ρυθμίσεις › Συνδέσεις › Μηνύματα SMS (`SmsConnectionSettings`), the tab «Μηνύματα SMS»
  in Στατιστικά & Μάρκετινγκ, Box › Ειδοποιήσεις switches, the post-booking question, the
  client card «Κινητό για μηνύματα», «Ενημέρωση συμμετεχόντων» in the class menu, the SMS box
  on «Θα έρθω» and the organiser's event SMS card.

## Amendment (v3.1 integration, 2026-11-03)

«Όχι τώρα» to the SMS question after a booking is kept with the person's account, as the walkthrough progress row `sms_ask_<slug>` with status `dismissed` (ADR-193), so no device asks again at that box. A refusal cannot live in `channel_contacts`, which needs a number. The device still remembers it at once.
