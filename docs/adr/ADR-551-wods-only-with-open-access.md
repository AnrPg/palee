# ADR-551: Workouts only while the member's access is open
Date: 2026-11-04
Status: Accepted

## Context
ANR (2026-11-04): a member with an unpaid charge could still open «Σήμερα»,
«Τα workouts μου» and «Πρόγραμμα» and read every WOD. The server refused
only the start of a workout (`StartWorkoutExecution`); every read of the
workout itself was open to any tenant member. "If his subscription is ended
he should not be able to see it." Mockups:
`/mnt/project-files/milos/member-wod-access/mockups-2026-11-04.html`.

## Decision
1. **One rule, in the domain.** `EntitlementPolicy.access_open/1` closes
   access only on a definite answer: `blocked` (unpaid after the overdue
   grace) or `inactive` (membership ended, expired, paused, cancelled, or no
   package). No finance profile (a gym that does not run finance), `active`,
   `grace`, and a package bought ahead (`upcoming_starts_on`, the earliest
   active subscription that starts after today, for `no_active_package`)
   keep it open.
2. **One application check**, `Application.AuthorizeWodAccess.call/2`: staff
   are never gated; everyone else gets the policy's answer for their
   effective entitlement. Every surface uses it, no one-off checks.
3. **Where it applies.**
   - `GET /my-workouts` answers 403 `finance_entitlement_blocked` or
     `finance_entitlement_inactive`.
   - `GET /workouts/:id`, `/workouts/:id/scales`, `/workouts/:id/goals`,
     `/workouts/:id/leaderboard`, `/workout-snapshots/:id` answer the same
     403 (`PaleeWeb.Plugs.RequireWodAccess`, per action), so a direct link
     opens nothing.
   - `GET /schedule` keeps the classes (times, coach, places) but drops each
     class's `workout` and the member's own version, and marks the slot
     `wod_locked: true`. Booking was already refused by the entitlement.
   - `GET /me/today` leaves out the programme and the box's WOD;
     `GET /community/wod-today` shows no WOD.
   - The member's own results (`/me/executions/:id/workout-snapshot`,
     the training log) stay theirs.
4. The web app hides what the member cannot use (vision §4 principle 11,
   ADR-470) and shows one notice with the way out (pay, renew, write to the
   box) on Box.

## Consequences
- A finance-enabled gym's member with no package at all no longer sees the
  WODs, matching booking and workout start, which already refused them.
- A season or package that starts later keeps the programme readable before
  its first day.
