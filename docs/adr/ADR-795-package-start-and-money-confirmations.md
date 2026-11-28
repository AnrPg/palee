# ADR-795: When a package starts, activation apart from payment, money confirmations
Date: 2026-11-28
Status: Accepted

## Context
ANR (thread «Ενεργοποίηση πακέτου χωρίς πληρωμή», mockups
`/mnt/project-files/milos/package-activation/`) asked for three things:

1. the box or independent coach chooses when a package's period and next payment day
   start: on the member's **first completed class or WOD** (default) or **on payment**
   (online purchase or the front desk). With the first, a package that changed while the
   member waited is shown to them (costs more: important, needs action; fewer benefits:
   serious; name or more benefits: warning) and starts once they press «Το κατάλαβα»;
2. starting a package must never need a payment that did not happen («+ Πληρωμή» with
   «Για: <πακέτο>» issued a paid receipt, reported to myDATA when connected);
3. «Έλαβες πραγματικά τα χρήματα;» before money is recorded, with «Να μην εμφανιστεί ξανά
   σήμερα», plus confirmations on other sensitive actions.

ANR picked every recommendation: «Ήρθε», or the class ended without «Δεν ήρθε»; a coach's
member marks the first WOD done; the per-package «Έναρξη ισχύος» goes; a package that now
costs more keeps the paid price for the first period; staff never override the start; two
buttons with a question about the money (2A); «+ Πληρωμή» for a package still starts it,
after the question; a dialog with a way out (3A); «don't show again today» on every device
of the account until the box's midnight; all ten confirmations of list 4.

## Decision
### Start (server)
- `finance_settings.package_starts_with`: `first_session` (default) | `payment`.
  Ρυθμίσεις › Πληρωμές «Πότε ξεκινά ένα πακέτο συνδρομής».
- Every assignment goes through `EctoFinanceStore.assign_package`. With `first_session`
  and no explicit `starts_on` (imports, seasons, backfills, benefits and operations pass
  one and start at once), the subscription is created **waiting**:
  `awaiting_first_session = true`, `ends_on`, `commitment_ends_on` and `charges_from`
  empty, no charge issued, `starts_on` provisional (the assignment day, so bookings and
  stacking keep working). Money taken for it (a desk receipt, an online purchase) counts
  against its first charge as before (ADR-274).
- A waiting subscription books like a running one. Allowances counted over the
  subscription period use the bounds `{starts_on, 9999-12-31}` while waiting; at start
  those entries are moved to the real first period.
- Waiting has no time limit.
- A row in `finance_package_starts` (one per waiting subscription) is the lineage: bought
  name, waiting since, the session that started it (`class` / `workout`, its id and day),
  the changes found, the severity, who acknowledged and when, `status`
  `waiting` → `review` → `started` (or `started` directly).
- **What starts it** (gym-local day): attendance recorded as `attended` (staff, self
  check-in, QR scan: `:attendance_recorded`); an hourly sweep for classes that ended with
  the booking still approved and no `no_show`/`missed`/`cancelled` attendance; a result
  of the box's or coach's WOD finished or logged by the member (`:workout_result_recorded`
  now carries `user_id`).
- **Changes while waiting**: the bought terms (the subscription snapshot; ADR-770 no longer
  counts waiting subscriptions as holders) against the package now, using
  `PackageTermChanges.changes/2` and `direction/3`. Price up → `important`; any term worse
  for the member → `serious`; name changed, price down or a term better → `warning`.
  Billing period, purchase-only and structural terms are not taken (as for holders).
- No change: the package starts on the session's day. A change: `review`; the member is
  told (bell + push `package_start_review`), bookings are refused
  (`finance_package_review_required`) until «Το κατάλαβα», which starts the package that
  day with the package's current terms. 1δ: the first period is charged at the bought
  price; the new price applies from the next payment (`price_cents_snapshot` is updated
  right after the first charge).
- Start = `starts_on`, `ends_on` (validity), `commitment_ends_on`, `charges_from` (when
  billable), `activated_on`, first charge issued.
- The per-package «Έναρξη ισχύος» (`terms.validity_starts`) is removed from the catalog
  and from stored package params; subscriptions sold before keep the old first-reservation
  rule (`activate_on_first_use!`), so nothing already sold changes.

### Activation apart from payment (web)
- Ledger and member profile: «Ενεργοποίηση πακέτου» asks «Τα X €»: «Θα πληρώσει αργότερα»
  (debt, as «Ανάθεση» did), «Τα πήρα τώρα» (opens «Καταγραφή πληρωμής» for that package),
  «Χωρίς χρέωση» (an ADR-612 free package benefit, written with who and why).
- The line under it says when it starts, from the box's setting.

### Confirmations
- `finance_confirmation_skips` (user, organization, kind, day in the box's time zone):
  «Να μην εμφανιστεί ξανά σήμερα» for the money questions only. Every skip is logged.
- Money questions (skippable): recording a payment (cash, POS, transfer, other), desk
  «Εισπράχθηκαν» / «Είσπραξη», e-shop pickup paid at the desk, cash refund.
- Always asked: forgive a debt, manual credit, free package; cancel a class with the number
  of people booked; a message to the whole box with the number of recipients; a package
  price or terms change with holders (ADR-770 already asks); a staff role change (what the
  role will see); a CSV export with personal data (how many people).

## Consequences
- Boxes switch to `first_session` by default: a package sold from now on starts on the
  member's first class. Packages already sold do not change.
- The ledger shows «Ξεκινά με την πρώτη προπόνηση» for a waiting package and «Περιμένει
  να δει τις αλλαγές» while in review; the member's package card says the same.
