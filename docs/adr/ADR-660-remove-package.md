# ADR-660: Remove a member's package completely

Status: Accepted (ANR, 2026-11-17)
Builds on: ADR-220 (renewal and leaving), ADR-274 (member status), ADR-595 (leaving ends box membership), ADR-612 (gift or grace), ADR-155 (the undo minute)

## Context

Staff could change a member's package but never take it away: the picker in
the members table offered only other packages. ANR asked (2026-11-16) to be
able to remove a package completely. Picks from the mockups
(`/mnt/project-files/milos/remove-package/`): 1A, 2B, 3 (rest stays owed),
4A, 5 bell + push, 6 optional reason with «Να τον δει και το μέλος», 7 undo
toast, 8 front desk removes but never writes off.

## Decision

- **Where**: a red «Αφαίρεση πακέτου…» link in the Πλάνο popover of the
  members table, under «Ανάθεση». It opens a dialog that says what happens
  before staff confirm (`GET …/subscriptions/:id/removal` preview).
- **Effect**: the subscription becomes `cancelled` with `removed_on` = today
  and gives nothing from today. Member status (ADR-274) reads a removed last
  package as «Χωρίς πακέτο» with no access, the same for member and staff.
  Box membership is separate (ADR-595): a member who already left loses box
  access from yesterday or the last day of another package still held.
- **Money is separate**: an unpaid invoice nobody paid anything on is either
  cancelled or kept owed, chosen by staff each time with nothing preselected,
  and only by roles with `manage_billing`. The front desk (`take_payments`
  only) can remove a package but the debt always stays. A partly paid invoice
  keeps its remainder owed. Paid money stays; the dialog links to the refund.
- **Undo minute**: the removal can be undone for 60 s from the toast
  «Αναίρεση», which restores the subscription, cancelled invoices (with their
  referral rewards) and box access. Settlement runs after it
  (`SettlePackageRemovalJob`, with the daily `SubscriptionExpiryJob` as a
  safety net): upcoming bookings are cancelled (unless another package or
  grace still covers them) and the member gets a bell and push notification
  `package_removed`, with the reason only when staff ticked the box.
- **Record**: `finance_package_removals` (tenant table with RLS) keeps who,
  when, the roles, the choice, the cancelled invoices, the reason and what
  was settled. One open removal per subscription.
- **API**: `POST …/finance/members/:id/subscriptions/:subscription_id/removal`
  (`invoice_choice`, `reason`, `reason_shared`) and
  `DELETE …/finance/members/:id/package-removals/:removal_id`, both
  `take_payments`; errors `subscription_not_removable` 409,
  `invoice_choice_required` / `invalid_invoice_choice` 422,
  `write_off_not_allowed` 403, `removal_not_undoable` 409.

## Consequences

- No silent write-offs: every cancelled invoice is tied to a removal record
  and a role allowed to do it.
- The member is told once, after the undo minute, so an undone mistake
  never reaches them.

## Addendum (2026-11-28): a removed charge never comes back; «Αλλαγή πακέτου» replaces

ANR's report: a member's monthly invoice, purged in «Εκκαθάριση συναλλαγών»
and the package switched to a free one, came back every day as overdue,
with the old package and «Ληξιπρόθεσμο».

Two root causes, fixed for every member:

1. **The hourly billing re-issued voided and purged charges.** It counted
   a period as charged only while its charge was live, so once staff voided
   or purged it, the next run issued a fresh one (new number, issue date
   today, due on the period start: 21 Nov in the profile, 27 Nov in the
   purge search). Now `SubscriptionCharges.charged_starts/1` counts every
   charge ever issued, paid, open, voided or purged: a period is charged
   once, and a charge staff took away is never issued again by Palee.
   Staff who want it after all add a charge by hand. Package term changes
   (ADR-770) read the same rule.
2. **«Αλλαγή πακέτου» added a second package.** The ledger's package menu
   (titled «change») only assigned the new package; the old one stayed
   active, kept renewing and kept its debt. Now, for a member who holds a
   package, picking another opens the removal dialog as «Αλλαγή από X σε Y»:
   the same removal (unpaid invoice void or kept, reason, record, undo) with
   `replacement_package_id`, and the new package starts in the same
   transaction. The removal row keeps `replacement_subscription_id` and
   `replacement_package_name`; the member is told «changed from X to Y»
   (bookings are kept, the new package covers them); undo also takes the new
   package back (refused once money was taken for it). Picking the same
   package again starts it afresh: a clean slate. «Πρόσθεσέ το ως δεύτερο
   πακέτο» keeps adding a package beside the current one, on purpose.
   The member panel lists «Αφαίρεση πακέτου…» on every package held, so an
   old second package can be ended too.

Existing data is not changed by a migration: staff end a stray old package
with «Αφαίρεση πακέτου…» (voiding its invoice), and it stays ended.
