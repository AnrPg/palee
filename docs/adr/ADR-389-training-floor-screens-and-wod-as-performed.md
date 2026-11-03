# ADR-389: Training floor screens and «the WOD as I performed it»
Date: 2026-11-02
Status: Accepted

## Context
The product owner (ANR) picked the v3.1 «Προπόνηση και floor» mockups (`v31-mockups/board/w5-training.html`)
on 2026-11-02: d2 A, d3 A, d6 A, e1 B, e4 A, e5 A, d5 A. ADR-356..359 built the API. One piece was
missing for d3 A: the Journal should show the WOD «όπως ήταν» **only when the WOD changed since** the
run or score. ADR-357 stored `workout_snapshot_id` on executions and training-log entries but no
endpoint exposed it to the person, nor whether the WOD now reads differently.

## Decision
### API
- `GET /api/org/:slug/me/executions/:id/workout-snapshot` and
  `GET /api/org/:slug/me/training-log/entries/:id/workout-snapshot` (`WorkoutSnapshotController`
  `:execution`, `:training_log`) return `{snapshot, changed}` for the person's **own** run or score:
  `snapshot` is the ADR-357 snapshot (`null` for results from before snapshots), `changed` is true when
  the WOD's current content hashes differently (`WorkoutSnapshot.same?/2`) or the WOD no longer exists.
  Someone else's holder, or an unknown id, is `404 workout_snapshot_not_found`.
- Port callback `WorkoutSnapshotStore.own_snapshot_id/4` reads the holder's snapshot id only when the
  holder belongs to the user (tenant-scoped, under RLS). Application:
  `WorkoutSnapshots.as_performed/3`. No migration.

### Screens (web)
- **d2 A** (`WodLeaderboard` in the #wod card): chips Όλοι · my division · my age group · my level;
  the percentile («top 30%», «καλύτερο από το 70% των σκορ») on my own row; period, branch (my home
  branch) and buddies under «Προχωρημένα». People who did not opt in keep the card's existing list.
  Division and birth year are set in Εγώ › Κοινοποίηση › Leaderboard once opted in.
- **d3 A**: a word tag per day in the staff schedule («Χωρίς WOD», «Μερικά με WOD · 1/3»,
  «Όλα με WOD»; «Χωρίς τμήματα» only in the month grid, since the day/week columns already say a day
  has no classes). In the Journal, a run or score whose WOD changed shows «Το WOD άλλαξε από τότε» with
  a link to the snapshot.
- **d6 A**: «Επίπεδο φυσικής κατάστασης» in Ημερολόγιο › Πρόοδος: a bar per domain, «Γιατί;» with the
  PRs and points, «Τι να δουλέψεις», the standards (neutral by default) under «Προχωρημένα», kept on
  the device. The anchors are marked as needing coach review (code comment in `FitnessBenchmarks`).
- **e1 B**: «Νέοι σήμερα (n)» (first visit or trial) on top of the class roster; every row and the
  desk check-in card carry the ADR-359 badges in words.
- **e4 A**: after a booking, once per person on the device, «Να μπαίνουν οι κρατήσεις στο ημερολόγιό
  σου;» (Apple Calendar, Google Calendar, «Όχι τώρα»), subscribing to the existing private feed. A
  booked class's «add to calendar» now downloads the server invite (same UID as the feed).
- **e5 A**: the profile's notes field gains «Ποιος τη βλέπει» (Όλο το staff / Μόνο εγώ); a coach
  starts from «Μόνο εγώ», others from the staff. The front desk (`view_directory`) sees and writes
  only staff notes, in a «Σημειώσεις για το staff» panel.
- **d5 A**: «Στείλε βίντεο τεχνικής στον coach» on the completion screen when the package includes
  technique videos with some left; it sends the run's `execution_id` (ADR-098).

## Rationale
A per-holder read keeps the Journal feed (an account-wide read model across boxes) unchanged and
costs one small tenant-scoped request only for WOD-linked entries. Comparing hashes on read follows
ADR-357: nothing to keep in sync when a WOD is edited.

## Alternatives Considered
- Adding `workout_snapshot` to every Journal feed entry: the feed spans boxes and would need a
  tenant context per entry.
- Showing the snapshot on every result: the mockup and ANR want it only when the WOD changed.
- Storing the calendar offer's answer on the server: one question, once; a per-device flag is enough
  and never blocks anything. Open question in the report.

## Consequences
- The calendar offer can appear once more on another device.
- The front desk sees a «Σημειώσεις για το staff» panel in the member profile's coaching tab.
- Fitness standards are a device preference, not shared with the box.

## Implementation Notes
Branch filtering uses the membership's `home_location_id`; the branch choice is hidden without one.

## Amendment (v3.1 integration, 2026-11-03)

- The calendar offer at the first booking is answered once per person on every device: the answer is the walkthrough progress row `calendar_offer` (ADR-193), `completed` for Apple or Google and `dismissed` for «Όχι τώρα».
- ADR-358 amendment: injuries name body parts, not fitness domains, so with an active injury and no known injured domain «Τι να δουλέψεις» suggests nothing and shows only the injury note.
