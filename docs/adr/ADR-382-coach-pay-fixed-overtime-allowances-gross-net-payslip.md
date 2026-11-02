# ADR-382: Coach pay adds fixed pay, subscription commissions, overtime and allowances, lines by hand, gross/net and an internal pay statement PDF
Date: 2026-11-01
Status: Accepted

## Context
The product owner (2026-11-01) asked to extend coach pay (ADR-341): a
fixed amount per month, week or day; a percent of the subscriptions of a
coach's own clients or of the whole box; several rules at once with the
statement showing each; payments by hand with a reason; the box's own
overtime and allowances; a PDF per person and period; a statement list for
the staff profile and a summary for Finance. Follow-up answers the same day:
overtime is hours above a weekly threshold paid per hour (no other
measure, no invented defaults); every line is `gross` or `net` (default
gross), shown apart and never summed into one unlabelled figure; net lines
are marked; a `non_taxable_reimbursement` line kind with a required note;
no flag that would hide a line from records or exports.

UI waits for mockups: this ADR covers domain, API and tests only.

## Decision
1. **Fixed pay**: rule kind `fixed` with `amount_cents` and `frequency`
   (`monthly`, `weekly`, `daily`), prorated by the calendar days the rule
   is valid in the period (gym-local dates, ADR-176/179):
   `daily` one line (days × amount); `weekly` one line (amount × days ÷ 7);
   `monthly` one line per calendar month (amount × days in that month ÷
   days of that month, so a full month pays exactly). Every divided amount
   is `unit × quantity ÷ quantity_divisor` in integer cents, rounded half
   away from zero once per line (`Domain.Proration`).
2. **Subscription commissions**: `percent_of_sales` gains the scopes
   `own_clients` (subscription and package payments of members the coach
   coaches through a coaching relationship, ADR-100, on the day paid, or
   whose personal-training coach they are) and `box_all` (every
   subscription and package payment of the box). Both count only
   `membership` and `package` revenue (ADR-190); a payment that both a
   coach's `personal_training` rule and `own_clients` rule count is paid
   once, by `personal_training` (product owner, 2026-11-02); refunds are clawbacks
   attributed by the day the refunded payment was made; `card_surcharge`
   stays excluded. `sold_by` and `personal_training` are unchanged. The
   work source reads relationships through `Coaching.relationships_between/3`.
3. **Combined rules**: a person may hold any number of active rules of any
   kinds (already true in ADR-341, kept). Each statement carries `groups`:
   one per rule (its clawbacks included), per pay item and per kind of
   line added by hand, with the terms they were paid by (snapshotted on the
   statement as `rule_terms` at calculation, so an approved statement keeps
   them), quantity, unit rate and total. Groups never mix bases.
4. **Lines by hand** on `POST …/adjustments` with `kind`: `adjustment`
   (as before), `ad_hoc` («Έκτακτη πληρωμή», positive, required `note`)
   and `non_taxable_reimbursement` («Μη φορολογητέο», positive, required
   `note`). Who added a line (`created_by_id`) and when (`inserted_at`)
   are returned. Lines added by hand (`source_type = manual`) survive
   recalculation and are the only ones that can be deleted.
5. **Overtime and allowances**: tenant table `coach_pay_items` (forced
   RLS, tenant trigger, audit, TenantDataPolicy `coach_pay`): `kind`
   `overtime` (`per_hour`, required `weekly_threshold` hours 0..168) or
   `allowance` (`per_period` or `per_occurrence`, no threshold), name,
   amount, currency, `amount_basis`, `roles` (owner, admin, head_coach,
   coach, front_desk, accountant, janitor; `head_coach` = a coach with
   `coach_scope: all`, who also holds `coach`). Managed with
   `manage_settings`; read with `manage_settings`, `view_finance_reports`
   or `manage_billing`. Overtime is calculated: the scheduled minutes of
   the classes a person led per Monday–Sunday week above threshold × 60,
   paid amount × minutes ÷ 60; a week the period cuts gets the threshold
   prorated by its days in the period, rounded down. Allowances are added
   by hand per person (`POST …/periods/:id/pay-items`) when the item
   applies to one of the person's roles. Archived items are neither
   counted nor added; their lines stay.
6. **Gross and net**: `amount_basis` (`gross` default, `net`) on rules,
   pay items and every line; lines inherit it from their rule or item and
   staff may change it per line in a draft period
   (`PATCH …/periods/:id/lines/:line_id`; product owner, 2026-11-02: a
   basis staff chose on a calculated line is kept when the period is
   recalculated, matched by rule or pay item, kind, source and day). Lines
   by hand default to `gross`, except `non_taxable_reimbursement`, which
   defaults to `net` (product owner, 2026-11-02). Statements and periods keep
   `gross_cents` and `net_cents`; `total_cents` stays (ADR-341) and is
   documented as the sum of all lines. Each line carries
   `deviates_from_default` (true when net) and each statement
   `net_line_count`. The CSV adds `note` and `amount_basis` columns at the
   end. Palee computes no taxes or contributions; there is no flag that
   hides or excludes a line.
7. **Pay statement PDF** («Εκκαθαριστικό»), reusing `Palee.Pdf` and
   Liberation Sans (ADR-245): business identity (fiscal identity or the
   box name), person, period and approval date, the groups with their
   terms and quantity × rate, the lines added by hand with notes, net rows
   marked «Καθαρά», and the total line «Μικτά X · Καθαρά Y». Headed and
   footed «Εσωτερική κατάσταση αμοιβής» with the statement that it is not
   an official payroll document. Labels from gettext domain `coach_pay` in
   the 12 locales; drawn in el, en, de, fr, it, nl, es, pt-PT, ru, bg
   (the PDF writer lays out left to right only, so ar and he are refused
   with `unsupported_language`). Approved or exported periods only.
   `GET …/coach-pay/periods/:id/statements/:user_id/pdf` (view_finance_reports,
   manage_billing) and `GET …/coach-pay/mine/:period_id/pdf` (one's own).
8. **Visibility**: `GET …/coach-pay/people/:user_id/statements` (the staff
   profile, Finance capabilities, every status, totals per currency gross
   and net) and `GET …/coach-pay/summary?from&to` (per period, per person).
   `GET …/coach-pay/mine` adds totals and, with the PDF, moves to the
   capability-checked admin scope so every paid staff role (front desk,
   accountant, cleaning) reaches their own; the service only reads the
   caller's own statements.
9. **Payees**: rules, lines and allowances may name any staff member
   (owner, admin, coach, front desk, accountant, janitor), not only coaches.
10. **Records**: 10-year retention, GDPR export (lines with their new
    columns are already covered through `coach_pay_statements`) and account
    deletion (`palee_user_has_retained_records` covers every statement)
    stay as in ADR-341; `coach_pay_items` holds no personal data.

## Rationale
Extending the ADR-341 context keeps one place for pay. A divisor on the
line makes every prorated or hourly amount reproducible from the line
itself. Snapshotting terms on the statement keeps approved statements
stable. Separate gross and net subtotals avoid a figure that mixes bases.

## Alternatives Considered
- **A separate kind for subscription commissions**: duplicated the
  percent logic; a scope on `percent_of_sales` is additive.
- **Overtime counted in extra classes or added by hand**: proposed, but
  the product owner chose hours above a weekly threshold only.
- **Prorating weekly pay per ISO week**: more lines and the same total
  within rounding; one line per rule is simpler to read.

## Consequences
- A coach holding both `personal_training` and `own_clients` rules is paid
  once on a PT package payment, at the `personal_training` rate.
- A line's basis choice survives recalculation only while the line keeps
  its identity; a line whose source disappears goes with its choice.
- The statement PDF in Arabic and Hebrew waits for right-to-left support
  in `Palee.Pdf`.

## Implementation Notes
- Migration `20270501200000_coach_pay_plus`.
- Domain: `Proration`, `Overtime`, `PayItemPolicy`, `StatementGroups`,
  `AmountBasis`, `Payslip`; ports `WorkSource.coach_clients/3`,
  `WorkSource.staff_roles/1`; store callbacks for items, totals and basis.
- Endpoints under `/admin/coach-pay`: `items` (GET, POST, PATCH `:id`,
  POST `:id/archive`), `periods/:id/pay-items`, `periods/:id/lines/:line_id`,
  `periods/:id/statements/:user_id/pdf`, `people/:user_id/statements`,
  `summary`, `mine/:period_id/pdf`.
