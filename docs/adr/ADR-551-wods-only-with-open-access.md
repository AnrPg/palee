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
4. The web app (ANR's picks 2026-11-07: 1A, 2A, 3B, 4A) shows what the
   closed access keeps shut greyed with a line lock and not pressable, with
   «Ανοίγει μόλις ενεργοποιηθεί η συνδρομή»: the WOD-of-the-day card, the
   «Τα workouts μου» tile on Box and its tab in the Box strip
   (`SectionTab.locked`, `HubActionTile lockedLabel`, `ui/LockIcon`).
   The membership card on Box keeps the notice and the way out (pay, renew).
5. Around it: the Box strip sits in the logo's centred column (1A); Box has a
   «Τα workouts μου» tile next to «Πρόγραμμα» (2A); the WOD goals show as a
   quiet «Στόχοι» block of label/value rows under the WOD, with a small
   figure that opens the atlas sheet (4A).

## Consequences
- A finance-enabled gym's member with no package at all no longer sees the
  WODs, matching booking and workout start, which already refused them.
- A season or package that starts later keeps the programme readable before
  its first day.
