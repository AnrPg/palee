# ADR-347: Members at risk («Σε κίνδυνο»): an explainable score with reasons and a win-back hook
Date: 2026-10-31
Status: Accepted (CP-C7; builds on ADR-346)

## Context
Boxes lose members quietly; competitors show churn-risk lists (PushPress
"at risk", Wodify retention, Glofox churn prediction). Opaque ML scores do
not tell staff what to do and are hard to justify under GDPR art. 22.

## Decision
- A nightly job scores every active box member 0–100 from rules over
  their own data, each with a stated reason and its points:
  `attendance_drop` (last 4 weeks vs the 8 before, up to 40), `absent`
  (14+ days 25, 21+ days 35), `no_first_visit` (30), `no_upcoming_bookings`
  (10), `package_ending` (20), `payment_overdue` (15),
  `many_cancellations` (10), `new_member_slow_start` (10).
- Levels: high ≥ 60, medium ≥ 30, low otherwise; a suggested action
  (personal message, renewal offer, payment follow-up, check-in call).
- Staff (`view_members_at_risk`: owner, admin, front desk) see a list with
  reasons, mark «Επικοινώνησα» (who and when) and snooze for up to 90
  days.
- Entering high publishes `:member_at_risk` once per high spell; the
  `win_back` recipe (ADR-346) listens when the box switched it on.
- The score is never shown to the member and never decides anything on
  its own; it is a to-do list for people.

## Rationale
Rules with reasons are explainable, cheap and work from day one with no
training data; the weights can be tuned later from outcomes.

## Alternatives Considered
- A trained churn model: needs data we do not have per box and is opaque.
- Showing only "days since last visit": misses payment and booking trends.

## Consequences
- Community signals (buddies, posts) and consistency streaks are not used
  yet (open question).
- `retention_risks` is in the person's GDPR export and removed with the
  account.

## Implementation Notes
- Migration `20270502200000_create_retention_risks`.
- `Palee.Retention.Domain.RiskScore` (pure), `EctoSignalReader`
  (attendance, bookings, packages, invoices), `RefreshMemberRisksJob` at
  03:30.
- Endpoints `/api/org/:slug/admin/members-at-risk` (index, show, contacted,
  snooze).
