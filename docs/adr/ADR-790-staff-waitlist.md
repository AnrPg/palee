# ADR-790: Staff put a member on a class waitlist
Date: 2026-11-28
Status: Accepted

## Context
ANR's to-do of 2026-11-28: besides the automatic waitlist, the owner, office
staff or a coach must be able to put someone on a class's waitlist. Until now
only the member joined a waitlist (ADR-097, `JoinClassWaitlist`). Staff saw
the list on the class page but could not add anyone, and «Κράτηση ή
μετακίνηση» on the profile (ADR-232) greyed full classes out.

Mockups: `/mnt/project-files/milos/manual-waitlist/manual-waitlist-mockups-2026-11-28.html`.
ANR's picks: **1C** (from the class page and from the profile), **2B** (staff
choose the place each time: «Στο τέλος» or «Πρώτος στη σειρά»), and α–ε yes.

## Decision
* `PlaceMemberOnWaitlist` (`POST /admin/users/:id/class-waitlist`, body
  `slot_id`, `position` = `end` | `first`) puts an active member of the box on
  the waitlist of a future, open, published, full class. A class with room
  answers `slot_not_full`; the caller books with `PlaceMemberInClass` instead.
* The package is checked as for a staff placement (`Finance.check_entitlements`
  dry run: covers the class, a visit left, not frozen); the package rule of
  ADR-633 and the documents gate do not apply (staff decide).
* `bookings.waitlisted_by_id` records the staff member;
  `bookings.waitlist_front_at` marks «Πρώτος στη σειρά». `BookingPolicy.waitlist_order/1`
  puts «first» entries ahead of everyone (the latest first), then package
  priority, then join time. The server numbers the staff roster
  (`waitlist_position`) so the web never re-derives the order.
* When a place opens, `PromoteClassWaitlist` promotes as before; an entry with
  `waitlisted_by_id` is approved at once even where the class asks for
  approval (pick β), like a staff placement. No «extra seat» over capacity
  (pick γ): staff raise the capacity instead.
* The member hears it: notification `booking_waitlisted_by_staff` (bell and
  push, category «Κρατήσεις»), with their place in line (pick α).
* Who (pick δ, `ClassPlacementAccess`): staff with `book_for_clients` or
  `manage_schedule` for members they reach and classes of their branches
  (ADR-100/186); a coach (`run_classes`) in the classes they run, a head coach
  in any class of their branches. The same rule now covers
  `PlaceMemberInClass` and `GetClassPlacementOptions?slot_id=`, so the class
  page's «+ Προσθήκη» works for the class's coach. The profile's whole list
  stays with staff who book for clients.
* Only members (pick ε): not online-programming athletes or followers.
* `GetClassPlacementOptions` marks full classes the member could wait for
  with `waitlist: true` and `waitlist_place` («Στο τέλος» place). A move never
  goes to a waitlist: the dialog keeps those classes closed while moving.

## Rationale
One server action and one authorization rule serve both entry points, so the
class page and the profile cannot drift. Recording who added an entry, rather
than a boolean, keeps the audit trail and decides the approval rule.

## Alternatives Considered
* Always at the end, with «Πρώτος στη σειρά» in a row menu (recommended 2C):
  ANR chose to decide the place each time (2B).
* A numeric position column: reordering would rewrite every row; a
  timestamp for «first» keeps inserts O(1) and the order stable.

## Consequences
* Removing someone from the waitlist or reordering later is not in this
  round (not picked); the member can still leave the list themselves.
* Coaches can now book members with room into the classes they run.

## Implementation Notes
* Migration `20271128170000_staff_waitlist_entries` (columns plus the
  notification type, rewriting the type check from the live constraint so
  parallel branches merge cleanly).
* Web: `AddToClassDialog` (class page), `WaitlistPositionPicker` (shared),
  `MemberClassPlacementModal`; i18n namespace `StaffWaitlist`.
