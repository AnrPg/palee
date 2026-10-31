# ADR-342: Purchase and booking rules per package, enforced by the API
Date: 2026-10-31
Status: Accepted

## Context
Packages already carry intro-only (`new_members_only`), once-only and
cancellation terms (ADR-226, ADR-228). Owners asked (CP-A8) to also
control who may buy, how many times, what must come first, and how many
classes a member may book per day, per week and at once, and for the API
(not only the screens) to enforce them.

## Decision
1. **Package fields** (catalog phase b, under «Προχωρημένα»):
   `terms.buyers` (`anyone`, `active_members`, `staff_only`),
   `terms.max_purchases_per_person` (1–100 or none),
   `terms.prerequisite_package_ids` (up to 20),
   `booking.daily_limit` (1–20), `booking.weekly_limit` (1–50),
   `booking.open_bookings_limit` (1–100). Stored in the package's
   entitlement plan; defaults keep today's behaviour.
2. **Purchase**: `SubscriptionSelection.eligible?/4` checks, in order:
   `package_staff_only`, `package_already_used`,
   `package_purchase_limit_reached`, `package_new_members_only`,
   `package_prerequisite_missing`, `package_active_members_only`. It runs
   on staff assignment (channel `staff`: staff-only allowed), online
   purchase and «Το θέλω» requests (channel `member`). `package_terms`
   returns the failing code as `eligibility` so the screen can explain it
   before checkout.
3. **Booking**: `Scheduling.Domain.BookingLimits` counts the member's
   active bookings by day and Monday–Sunday week in the gym's time zone
   and their future bookings; `SubmitBooking` refuses with
   `booking_daily_limit_reached`, `booking_weekly_limit_reached` or
   `booking_open_limit_reached` (422, with `limit`). Staff placement
   (booking window off) skips the limits.
4. **Cancellation windows** stay the package's existing late-cancel cutoff
   (ADR-226).

## Rationale
The checks sit in domain modules with the existing eligibility and booking
window rules, so every channel uses one code path.

## Alternatives Considered
- **Limits per membership instead of per package**: a member with two
  packages could not be limited per package.
- **Checking only in the web screens**: bypassable through the API and
  MCP tools.

## Consequences
- The new fields are hidden in the package editor until the mockup is
  approved.
- Staff can still place a member over a limit; whether they should is an
  open question.

## Implementation Notes
- No migration: fields live in the package's JSON plan.
