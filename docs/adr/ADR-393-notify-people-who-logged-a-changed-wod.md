# ADR-393: Telling the people who logged a WOD that it changed
Date: 2026-11-03
Status: Accepted

## Context
ADR-357 snapshots a WOD when a score is logged or a run completed, and ADR-389 shows «Το WOD άλλαξε
από τότε» in the Journal when the WOD now reads differently (`changed`). Nobody was told when a coach
edited a WOD people had already done: the existing `workout_changed` notice goes to people booked in
its classes or assigned it (the WOD they are about to do). The product owner (ANR, v3.1 questions of
2026-11-03, item 11) asked to notify **only the people who logged it**.

## Decision
- **Who**: `Workouts.Domain.LoggedWorkoutChange.recipients/3` (pure) over every finished run and every
  score not voided whose snapshot belongs to the WOD (new port callback
  `WorkoutSnapshotStore.list_performed/2`, tenant-scoped under RLS): the people whose snapshot hash
  differs from the WOD's content after the save (exactly those whose Journal now shows «Το WOD άλλαξε
  από τότε»), one entry each, their latest run or score, never the editor. Results from before
  snapshots have nothing to compare and are left alone, as the Journal does. Nobody else hears it.
- **When**: once per save. `PublishWorkout` (the editor's and the DSL publish) calls
  `Application.LoggedWorkoutChangeNotice.notify/2` after a publish succeeds; the save is the burst, no
  timer. A substitution (a new WOD for one class or assignment) skips it: the old WOD is unchanged.
  A failure is logged and never fails the save.
- **What**: notification type `logged_workout_changed` (migration `20270515000000`, the type check
  rewritten from what the database holds), category `coach`, so the person's «Coach» switches apply
  to the bell and to push (ADR-199). Payload: `workout_id`, `workout_title`, `holder`
  (`execution` | `training_log`), `holder_id`, `url` `/journal?entry=<holder id>`. `dedupe_key`
  `logged_workout_changed:<workout id>:<content hash now>`: a retried request, or a save back to the
  same content, adds nothing. Push copy in the `notifications` gettext domain, bell copy in
  `TrainingFloor` (12 locales): «Το WOD άλλαξε» / «Το «Fran» άλλαξε αφού το έκανες. Δες το όπως ήταν
  στο Journal σου.».
- **No double notice**: people told by this notice are left out of the same save's `workout_changed`
  (bookings and assignments of the WOD); everyone else booked or assigned still gets that one.
- **Web**: the bell shows the new type (in its workouts filter) and opens the payload's URL; in
  the Journal the entry's «Το WOD άλλαξε από τότε» line (`WodAsPerformed`) is scrolled into view and
  outlined when the page was opened with `?entry=<its id>`.

## Rationale
- Comparing snapshot hashes with the WOD's content is the rule the Journal already uses, so the link
  always lands on an entry that shows the change.
- One notice per person per save, about the latest result, keeps a burst of edits (one publish) to one
  notice, without a timer or a queue.

## Alternatives Considered
- A debounce timer (say ten minutes) over several publishes: a second publish is a new decision of the
  coach and may change the WOD again; the dedupe key already drops a save that changes nothing.
- Notifying everyone booked into the WOD's classes: that is `workout_changed`, unchanged.
- A new category («Journal»): the edit comes from the coach; people who silence coach notices expect
  this one silenced too.

## Consequences
- ADR-357's note applies: a save that rewrites exercise rows with the same words makes a new
  snapshot, so it reads as «changed» in the Journal and is notified too.
- An entry older than the Journal's loaded pages is not scrolled to until the person loads that page.
- No new person data: notifications are already in the data download.

## Implementation Notes
- Tests: `test/palee/workouts/domain/logged_workout_change_test.exs`,
  `test/palee_web/controllers/logged_workout_change_test.exs` (API under RLS: only loggers, never the
  editor, once per save, latest entry, muted category, no double notice for a booked logger, the
  link's entry reads `changed: true`), push builder, web vitest (`training-floor.test.ts`,
  `notification-links.test.ts`).
