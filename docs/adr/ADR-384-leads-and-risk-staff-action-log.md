# ADR-384: Leads and members at risk: every staff action is logged with who and when, and the staff screens show it
Date: 2026-11-02
Status: Accepted (v3.1 W2 UI; builds on ADR-344, ADR-347)

## Context
The product owner decided for the v3.1 W2 screens that every «contacted»
or other action on a lead or on a box member «Σε κίνδυνο» is logged with
WHO did it and WHEN, and that the staff screens show that log.

Leads already keep a full history (`lead_events`, ADR-344) with the acting
staff member on every event: stage moves, notes, «Επικοινώνησα», next steps,
owner changes, conversion and the marketing opt-out. Members at risk did
not: `retention_risks` holds only the latest `contacted_at` and
`contacted_by_id`, and «Αργότερα» (snooze) kept no author at all, so an
earlier contact was overwritten by the next one.

## Decision
- A new tenant table `retention_risk_actions` (forced RLS, the tenant
  context trigger): `user_id` (the box member), `actor_id` (the staff
  member, nulled if their account goes), `kind` (`contacted`, `snoozed`,
  `unsnoozed`), `channel` for a contact, `snoozed_until` for a snooze, `at`.
- `POST …/members-at-risk/:user_id/contacted` and `…/snooze` write one row
  each, with the caller as actor.
- `GET …/members-at-risk/:user_id` answers `{member, actions}`: the risk
  and the last 50 actions, newest first, each with the actor as a person.
  The list keeps showing the latest contact (`contacted_by`, `contacted_at`).
- The log goes with the risk: when the daily job drops a former box
  member's risk, their action log is removed too.
- Person data: the member's own rows are in their GDPR export (without the
  staff member's id) and go with account deletion (`ON DELETE CASCADE`);
  the box's tenant export and purge include the table (retention policy).
- The web staff screens show the logs: the lead panel's «Ιστορικό» (who ·
  when per event) and the «Σε κίνδυνο» member's «Ιστορικό ενεργειών».

## Rationale
A separate append-only log keeps `retention_risks` the small "latest
state" row the nightly job recomputes in place, while the history needed
for accountability ("who called Kostas, and when") is never overwritten.

## Alternatives Considered
- Keep arrays of contacts on `retention_risks`: rewritten on every nightly
  refresh, unbounded, and harder to export per person. Rejected.
- Reuse `lead_events` for members: members at risk are not leads; mixing
  them would make lead reports and GDPR scopes wrong. Rejected.

## Consequences
- One more tenant table in the audit list, the retention tenant data
  policy and the personal-data catalogue.
- Snoozing to 0 days («Εμφάνιση ξανά») is logged as `unsnoozed`.

## Implementation Notes
- Migration `20270509000000_create_retention_risk_actions`.
- `Palee.Retention.RiskAction`; `RiskStore.add_action/3` and `actions/3`.
- Web: `apps/web/src/components/admin/leads/*`, `apps/web/src/components/admin/at-risk/*`.
