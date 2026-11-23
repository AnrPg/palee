# ADR-760: The box's «Αρχείο ενεργειών»: every staff change, who, when and why
Date: 2026-11-23
Status: Accepted (complements ADR-612 «Δώρο ή χάρη», ADR-660 package removal, ADR-220 leaving)

## Context
The product owner asked (2026-11-23) whether the reasons staff type into popups (end date of a package, manual status, freezes, gifts, removals…) are kept in one ledger. They were not: each feature kept its own history, many changes kept none. Clickable mockups were discussed; the picks were 1A–11A and 12B.

## Decision
- **One table, insert-only.** `activity_log_entries` (RLS by tenant): `action` (a key of `ActivityLog.Domain.Actions`), its `area` (members, money, packages, classes, training, spaces, shop, community, communication, staff_pay, settings), `actor_user_id` and `actor_roles` then, `person_user_id`, `subject` (the ids the request named), `subject_label`, `details` (e.g. `changes: [{field, before, after}]`), `reason`, `reason_shared`, `sensitive`, `source` (request, backfill, system), `source_ref`. A trigger refuses every update except forgetting a person; no delete outside the organization purge (8A). A correction is a new entry.
- **What is logged (3A).** Every mutating staff route. `PaleeWeb.RouteActivity` maps each `{controller, action}` of the `:admin_only` and `:staff_only` pipelines to an action key or `:skip`; `route_activity_test.exs` fails the build when a new route is not classified, and when a key is unused. The plug `RecordActivity` writes the row after a 2xx response (not a replay, `"replayed": true`) in `before_send`. Use cases add what the route alone does not say with `Palee.ActivityLog.note/1` (the person, before/after values, a label). The row is written after the change commits, not in its transaction: a failed write is logged and counted in telemetry (`[:palee, :activity_log, :failed]`) but does not undo the change.
- **Where it shows (1A, 2A).** Διαχείριση › «Αρχείο ενεργειών» (`GET /admin/activity-log`): a timeline grouped by box-local day, filters (area, person, staff, dates, text), cursor paging, details on tap. The staff profile of a member has a tab «Ιστορικό» (`person_id`).
- **Who reads what (4A).** Capabilities `view_activity_<area>`. Owner and admin: everything. Accountant: money, packages, staff pay. Front desk: money, packages, members, classes, and their own pay. Coach: classes and their own pay. Janitor: their own pay. `:own` scope means rows about the reader.
- **The member (5A, 6A).** `GET /me/membership/activity` returns only rows about them with `reason_shared`, without the staff name (the web shows «Το box»). Every popup asking a reason about a member has «Να το δει και το μέλος», unticked by default, sent as `reason_shared`.
- **Reasons (7A).** Whether a reason is required stays per action as before.
- **Deleted accounts (9A).** Rows are kept forever. When an account is deleted, `palee_forget_activity_person(uuid)` (SECURITY DEFINER, only for a scheduled deletion) clears `reason` and `details` and sets `redacted_at`; names are resolved at read time, so the person shows as «Διαγραμμένο μέλος».
- **CSV (10A).** `GET /admin/activity-log/export` with the same filters, capability `export_activity_log` (owner, admin, accountant), at most 10 000 rows; cells starting with `= + - @` are quoted against formula injection.
- **Older records (11A).** `ActivityLog.Backfill` copies existing histories (overrides, freezes, gifts, removals, leaves, cancellations, credit notes…) with `source = backfill` and `source_ref = "<table>:<id>"` (unique, so idempotent), versioned per box in `activity_log_backfills`, by an hourly job.
- **Owner's daily summary (12B).** Actions marked sensitive (debt forgiven, credit notes, manual status, end dates, gifts…) are summarised to the owners each box-local morning, with a link to the filtered log.

## Consequences
- Migration `20271123163000_activity_log` (reversible). Both tables are in `Tenancy.Audit` and the ActivityLog `TenantDataPolicy` (purged with the box).
- New request field `reason_shared` on freeze, freeze cancel, value overrides, gifts and revokes, package assign/remove, leaving, package request decline, trial and season decline, rank revoke, shop order cancel.
- New capabilities change `AccessPolicy` and its tests.
