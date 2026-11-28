# ADR-805: A member's own WOD from the profile uses a class visit, not online programming
Date: 2026-11-28
Status: Accepted

## Context
ANR (2026-11-28): staff open a box member's profile and assign them a WOD made for them, as a coach would tell a member at the box "do this today". The class variation for one member (ADR-785) already covers a class the member booked, even mid-class (the part done so far stays, the new WOD covers the rest). The other profile mode, «Ξεχωριστή προπόνηση» (`personal`, a WOD for a day independent of any class), still required online programming or personal training (ADR-225). Box members are not online clients: they receive a WOD now and then and also book classes. Only athletes receive programming through assignments.

## Decision
For a **member** (not an athlete), `personal` mode follows the rules of a class booking:

1. A class booked that gym day (pending or approved): nothing more is used, because the booking already took its visit.
2. Otherwise the package must hold **class visits** (strictly, regardless of the tenant's rollout mode; a missing finance profile or a role never implies it), and Finance must let one more visit be used that day (limits, freezes, package dates, grace or gift, ADR-612/633). The WOD then uses **one class visit** (decision card "Χρεώνει 1 επίσκεψη"). It is reserved before the assignment is written and consumed once it is, with idempotency key `member-day-wod:<delivery>:<member>`, metadata kind `member_day_wod`.
3. With no class visit to use, online programming or personal training still serve as before (an online client keeps working, with a metered touchpoint).
4. Otherwise the answer is 403 `member_wod_not_covered` with `user_id`, `nickname`, `date` and the Finance `reason`.

The admin profile's `programming` payload gains `class_visits` (members only), so the web opens «Ξεχωριστή προπόνηση» for such members, hides the «not in package» notice and says in the mode's hint that it uses one visit unless a class is booked that day. Athletes are unchanged (ADR-225).

## Rationale
The WOD stands in for a class: the member trains at the box that day either way, so it costs what a class costs and never twice. Online programming would charge a member for a product they never bought.

## Alternatives Considered
- Free when the member is active (no visit): rejected by ANR on the decision card.
- Require online programming as before: contradicts ANR's semantics.

## Consequences
- Removing such an assignment does not give the visit back (the same as touchpoints today).
- Two separate day WODs on the same day without a booking use two visits.
- `UpdateAssignedWorkout` still checks newly added people through ADR-225.

## Implementation Notes
`Palee.Application.AuthorizeMemberDayWod` decides the grant; `ProgramUserWorkout.validate_target(:personal)` and `AssignWorkout.programming_grants/4` call it; `AssignWorkout.charged/5` turns `:class_visit` grants into Finance reservations alongside touchpoints. The multi-week programme assignment that was mocked first is parked as TD-212.
