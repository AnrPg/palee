# ADR-717: «Κρατήσεις πριν την πληρωμή»: the box chooses how many classes while «Το θέλω» waits
Date: 2026-11-21
Status: Accepted (amends ADR-633 «One class while waiting»)

## Context
ADR-633 lets a person whose «Το θέλω» waits to be paid at the front desk book ONE class, once per person and box. The product owner asked (2026-11-21) for this to be a box setting, "how many visits the member can do and classes to book … where the user clicks «I want it» and then is expected to pay at the front desk (e.g. no online payments or other similar cases). Default is 3 visits/bookings."

## Decision
- **One number, one counter.** A booking is what uses a visit, so "visits" and "bookings" are the same count here: each class booked while waiting counts one. `finance_settings.package_wait_bookings` (integer, 0–20, default 3, DB check constraint). 0 = no booking until the desk activates the package.
- **Where it is set.** Ρυθμίσεις › Πληρωμές, card «Κρατήσεις πριν την πληρωμή» (ui/Select, never a native select), shown with and without an online provider (a package can be paid at the desk either way). Catalog key `finance.package_wait_bookings`, verdict `:basic`.
- **Counted per person and box, for good.** New table `finance_package_wait_bookings` (one row per class booked while waiting, RLS by tenant), replacing the one-class columns `first_class_at` / `first_class_scheduled_class_id` on `finance_package_requests`; existing rows are copied over. A new «Το θέλω» does not start the count again (otherwise asking again would reopen free classes). The row keeps its count when its request is deleted (`on_delete: nilify_all`).
- **Server-enforced** in `PackageRule.check_booking/4` → `PackageRequestStore.claim_wait_booking/5`: in one transaction under a per-person advisory lock, it needs a pending request held today, refuses when the count has reached the box's number (`finance_package_required`, 403), and inserts the row. Two bookings at once cannot both take the last place.
- **Whatever happens to the booking** (as in ADR-633): a cancel does not give it back. The same class booked again after a cancel counts once (unique per person and class). A booking that fails after its place was counted gives it back.
- **Changing the number.** Lowering it keeps the bookings already made and refuses new ones until the count is under the new number; raising it opens more at once, for people already waiting too.
- **Declined or lapsed request** (unchanged, ADR-633 `end_waiting/2`): their upcoming bookings are cancelled.
- **Staff queue** shows «Έκανε X από N κρατήσεις πριν την πληρωμή» per request (`wait_bookings_used`, `wait_bookings_allowed`). `GET /me/package-rule` returns `wait_bookings_allowed`, `wait_bookings_used`, `wait_bookings_left` instead of `first_class_available`.
- Staff placing someone (`PlaceMemberInClass`, `package_rule: false`) are not counted or limited, as before.

## Consequences
- Migration `20271121171700_package_wait_bookings` (reversible: down keeps each person's earliest class on its request).
- The error text `apiErrorPackageRequired` no longer promises "one class".
