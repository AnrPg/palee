# ADR-500: The box's reminder schedule for a subscription that is not renewed
Date: 2026-11-04
Status: Accepted

## Context
ANR (2026-11-04) expected this schedule for a member whose subscription ends
without a renewal: some days before the end, on the day it ends, the day after,
then every 7 days, every step set by the box. The code only had one reminder
`subscription_expiry_reminder_days` before the end (default 5), one notice
after the end only while there were grace days, and the payment reminder every
`payment_reminder_interval_days` (default 7) for members who owe money.

## Decision
`SubscriptionExpiryJob` (daily, on the gym's clock) sends, per subscription
that is not renewed and whose member has not left (ADR-220):

1. `subscription_expiring` `subscription_expiry_reminder_days` before the end
   (0 = off), as before;
2. `subscription_expiring` with `days_left: 0` on the day it ends
   (`finance_settings.subscription_end_day_reminder`, default on);
3. `subscription_grace` on the day after
   (`subscription_day_after_reminder`, default on), now also without grace
   days; `grace_until` is set only while the member still has access;
4. `subscription_grace` with `followup: true` every
   `payment_reminder_interval_days` after that, until the member renews or
   leaves, also after the membership turned `expired`. A member who owes
   money gets the payment reminder (`PaymentReminderJob`) at the same pace
   instead, never both.

Each step has its own sent-at column (`end_day_notice_sent_at`,
`renewal_followup_sent_at`, migration 20271001000000) and its own dedupe key.
Both switches live under «Προχωρημένα» › Πληρωμές (catalog verdict Advanced).

## Rationale
The days-before and interval settings already existed, so the schedule reuses
them and only adds two switches. The follow-up repeats with the payment
reminder interval so the box sets one pace for every repeated reminder.

## Alternatives Considered
- A free list of reminder offsets per box: more flexible but more settings to
  understand; ANR asked for the fixed shape with box-set values.
- A separate follow-up interval: one more number with no request for it.

## Consequences
- Follow-ups have no end other than renewal or leaving, and payment reminders
  none other than payment: ANR (2026-11-04) chose no cap ("notifs forever
  until it is paid").
- Packages with their own reminder days (ADR-097) keep using
  `PackageExpiryReminderJob` for the days-before step.

## Implementation Notes
- `subscriptions_needing_expiry_notice/2` takes a kind and an options map.
- Notification texts in 12 locales (gettext `notifications`, web `Ui`).
