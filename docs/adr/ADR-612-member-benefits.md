# ADR-612: «Δώρο ή χάρη»: staff give a member something for free, with full lineage
Date: 2026-11-10
Status: Accepted

## Context
Boxes must be free to give things away or look away from a fee for whoever they like: let an overdue member keep training until a date, let someone train without a package, add a visit over a package's limit, give a package free or cheaper, or forgive a charge. Before this, those were five different tools in four places (the box-wide grace days, a manual «Δωρεάν» status with no end, allowance extensions in the advanced settings, an API-only package price, invoice void or a credit), and none of them said clearly who gave what and why.

The product owner picked (2026-11-10, mockups `gift-grace-mockups-2026-11-10.html`): A now, one «Δώρο ή χάρη» button on the member profile, and C later, «Ειδικές συμφωνίες» box rules for standing arrangements. All five kinds. Extra uses: staff choose the period each time. A grace always has an end date. Reminders stop during a grace and start again at its end. The member sees one quiet line (M1). The reason is optional. Only staff who take payments may give. "We must be very strict with observability, lineage and logging of such permissions of gifts/extra benefits (who did what, when, why etc)."

## Decision
- A new **insert-only ledger** `finance_member_benefits` (tenant RLS, forced). Each row is a `grant` or a `revoke` (a revocation names its grant, at most one per grant). A row keeps the kind, its dates, the money the box gave up (`amount_cents`), what it touched (`details`: usage entry, subscription, invoices and credit entries), the optional reason (max 500), the actor id, the actor's roles at that moment, the request id and an idempotency key. A trigger refuses every UPDATE. DELETE stays possible only for cascades and tenant purges (ADR-117).
- Kinds:
  - `grace` and `free_access`: they enter the entitlement snapshot as the fact `staff_access`. `InvoiceLifecycle.entitlement/1` makes access `active` with the source `staff_grace` or `staff_free_access` and `grace_until` = the last day. Cancelled or paused memberships stay closed. Payment reminders and renewal follow-ups skip these sources. The daily snapshot refresh ends them after the last day, so access and reminders resume by themselves.
  - Without a package, free access shows as the status `comped`.
  - `extra_uses`: a usage adjustment through `GrantUserAllowance` (period: calendar_week, calendar_month or subscription_period, always chosen), linked by `metadata.benefit_id`.
  - `package`: `AssignFinanceMemberPackage` either with charging from the next period ("free this period") or with `price_cents` (every period at that price). `amount_cents` is what the box gives up.
  - `debt_forgiven`: for each chosen invoice, a non-cash credit grant (`source_type = forgiveness`) and an `invoice_offset` of the open balance. The invoice ends up paid without money.
- No credit note is issued. Fiscal documents exist only for payments (ADR-240), and an unpaid charge has none, so pick 5 ("credit note automatically") never comes up.
- Grace, free access and extra uses can be revoked while they still count. A package or a forgiven debt is undone the usual way (end the subscription, a new charge).
- API: `GET/POST /admin/finance/members/:id/benefits` and `POST …/benefits/:benefit_id/revoke`.
  - Giving and revoking need `take_payments`. Reading also accepts `manage_billing` or `manage_memberships`.
  - Every call needs an idempotency key. A replay returns the first result with `replayed: true`.
  - Responses show the grant together with the names of the giver and the revoker.
- Observability:
  - Telemetry `[:palee, :finance, :member_benefit, :granted | :revoked]` (count and amount by kind) feeds the Prometheus metrics `palee_member_benefits_granted_total`, `palee_member_benefits_given_cents_total` and `palee_member_benefits_revoked_total`, and the periodic log reporter.
  - One `member_benefit_granted|revoked` info log line carries the full lineage: organization, membership, user, actor, roles, request id, dates and amount. It records whether a reason was given but not its text.
  - A refusal is logged as a warning.
- Member and staff read the same line (ADR-595): `standing.benefit` (`grace` | `free_access`) and `grace_until` give «Χάρη από το box ως …» or «Δωρεάν από το box ως …».

## Rationale
- One button keeps the staff's mental model small. One ledger gives the lineage the product owner asked for without spreading audit fields across five tables.
- Forgiving through a non-cash credit, and not through void, keeps the subscription from creating the charge again on the next renewal run, and keeps the invoice in the books.
- Grace through the entitlement fact reuses the snapshot, the reminders filter and the daily refresh. It needs no new job.

## Alternatives Considered
- B (actions where the problem shows) and C alone: rejected for now. C stays planned for standing arrangements.
- An audit-log table next to each existing tool: harder to read as one history and easy to miss a path.
- Void plus a new zero invoice for forgiveness: renewals would re-charge, and the books would lose the original charge.

## Consequences
- The old allowance extension form in the profile's advanced settings stays. Its rows are not linked to a benefit unless they were made from «Δώρο ή χάρη». Revoking a benefit's extra uses from there leaves the benefit shown as in effect (follow-up: hide or link those entries).
- C («Ειδικές συμφωνίες») is follow-up work.

## Implementation Notes
- The migration `20271112310000_member_benefits` also widens the credit ledger's `source_type` check with `forgiveness`.
- `finance_member_benefits` is in the tenancy audit and the Finance TenantDataPolicy, before the usage entries and memberships.
