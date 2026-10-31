# ADR-341: Coach pay and commissions as their own context, read from Scheduling and Finance through ports
Date: 2026-10-31
Status: Accepted

## Context
Boxes pay coaches per class, per attendee, per personal session or a
percent of the packages and PT they sell, and today work it out by hand
from class lists and payment exports (CP-A6). The figures must come from
the same records Palee already keeps (classes and attendance, personal
sessions, payments and refunds), be approved by the owner, exported for
the accountant, and never appear on fiscal documents.

## Decision
1. **New bounded context `Palee.CoachPay`** (ADR-043 layout) with four
   tenant tables (forced RLS, `palee_apply_tenant_context`):
   `coach_pay_rules`, `coach_pay_periods`, `coach_pay_statements`,
   `coach_pay_lines`.
2. **Rules per coach**: kind `per_class` (amount per class led, optional
   minimum attendees and class type), `per_attendee` (amount per attendee
   with chosen statuses: attended, late_cancel, no_show), `per_session`
   (personal sessions completed), `percent_of_sales` (bps of the payments,
   scope `personal_training` = PT packages coached by them, `sold_by` =
   sales they recorded). Valid from/to dates; archived, never deleted.
3. **Work through a port** `CoachPay.Ports.WorkSource` (classes, sessions,
   sales); the application adapter reads
   `Scheduling.coach_classes/3`, `Appointments.coach_sessions/3` and
   `Finance.coach_sales/3` in the gym's time zone. CoachPay never reads
   another context's tables. Refunds come back as negative sales and
   become `clawback` lines; `card_surcharge` rows are excluded.
4. **Periods** up to 92 days, no overlap: `open` → calculate (replaces all
   calculated lines, keeps manual `adjustment` lines) → `approved`
   (locked) → `exported` (CSV with a formula-injection guard). Reopening
   an approved period needs a reason; an exported one cannot be changed.
5. **Statements** per coach with lines, total and currency (from the fiscal
   profile). The coach reads only their own approved statements at
   `GET /coach-pay/mine`.
6. **Separate from fiscal documents**: no Finance or Fiscal write happens;
   statements are internal records, kept 10 years (TenantDataPolicy
   `coach_pay`, retention like accounting records), included in GDPR
   export and listed in `palee_user_has_retained_records` so a coach's
   account deletion keeps their statements.

## Rationale
A context of its own keeps payroll-like data apart from fiscal
documents and lets each source change behind a port. Reading at
calculation time (not on every event) keeps it simple and repeatable.

## Alternatives Considered
- **Lines written live on each attendance or payment**: many write paths
  in other contexts, harder to recalculate after a correction.
- **Payroll export only (no approval)**: owners asked to review and
  approve first.

## Consequences
- Calculation reads the whole period; a 92-day cap bounds it.
- Commission attribution for `sold_by` uses the staff user who recorded
  the payment (`created_by_id`); online member purchases have no seller.

## Implementation Notes
- Migration `20270501100000_coach_pay`.
- Endpoints under `/admin/coach-pay` (rules, periods, calculate,
  adjustments, approve, reopen, export) and `GET /coach-pay/mine`.
