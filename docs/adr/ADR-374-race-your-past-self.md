# ADR-374: Race your past self — split marks and the pace line
Date: 2026-10-31
Status: Accepted

## Context
CP-D7 (backlog, P2): BTWB shows a previous result as a virtual race with
splits. Palee already groups attempts at the same workout across providers
(`WorkoutIdentity`, ADR-162) and stores, per execution, the time per
section (`section_elapsed_ms`) and round counts, but no *when* each round or
segment ended, so a pace line was impossible. Vision §4.4: comparison with
yourself lives with the person, never with others.

## Decision
- **Split marks** (`execution_splits`, personal table): the timer (phone, or
  the watch through the phone) posts `%{segment_index, round, elapsed_ms}`
  — the end of a segment (`round` 0) or a finished round inside it (AMRAP
  taps, EMOM rounds). `Execution.Domain.SplitMarks` checks each mark against
  the execution's own timer segments and stamps its **section ordinal** (the
  section's position among real sections; transitions share their section's
  ordinal), so copies of one benchmark with different section ids still line
  up. Marks are idempotent on `(execution_id, segment_index, round)`, because
  an offline watch resends.
- **The previous attempt** (`Pacer.pick_previous/2`): newest completed
  execution of the same person with the same workout identity that finished
  before this one started; same scale level first.
- **The pace line** (`Pacer.compare/3`): checkpoints keyed
  `<ordinal>:<phase>:<round>:<n>`; `delta_ms` = this attempt − previous
  (negative = ahead), nil until reached; plus per-section times and, once
  completed, the total. `precision` says what the previous attempt allows:
  `rounds`, `segments`, `sections` (older executions, from
  `section_elapsed_ms`) or `finish`.
- API (user-scoped, `/api/executions`): `POST /:id/splits`,
  `GET /:id/pacer` (live during the run and in the results).
- RLS: the owner writes (`user_id = app.user_id`); reading follows the
  execution's own policy (`EXISTS` on `workout_executions`), so staff who
  may read the execution may read its splits.

## Rationale
Storing marks rather than recomputing from progress operations keeps the
server independent of the client's progress cadence and survives offline
batching. Ordinals instead of section ids make "same benchmark, other box"
comparable, which is the whole point of `WorkoutIdentity`.

## Alternatives Considered
- Derive splits from `execution_progress_operations`: they hold versions, not
  times or rounds. Rejected.
- A JSON column on `workout_executions`: conflicts with concurrent progress
  writes (optimistic lock) and with W5's executor work. Rejected.
- Compare with the person's best instead of the last attempt: a later option
  («Καλύτερη» in the mockup); last attempt is the calm default.

## Consequences
- The web and native timers must post marks (batched) — UI after ANR picks a
  mockup (W9 board, «Ο προηγούμενος εαυτός σου»).
- Training-log entries (manual logs) have no marks; they never become a ghost.
- GDPR: `execution_splits` is in the export (training) and goes with the
  execution and the account (FK cascade).

## Implementation Notes
- `Palee.Application.ExecutionPacer` (one service, two use cases) and
  `ExecutionTimerSequence` (the segments of an execution, shared with the
  watch plan).
- Migration `20270602100000_execution_splits.exs`.

## Amendment 2026-11-03: progress saves leave marks
`UpdateExecutionProgress` stores the marks a progress save implies
(`SplitMarks.from_progress/3`): every segment the save moved past ended,
and every new count in `segment_cycle_counts` (the AMRAP «Γύρος» taps)
finished that round, all at the save's `total_elapsed_ms`. Every timer
that saves progress (web, phone, box screen, the watch through the phone)
therefore feeds the pace line without posting marks. `POST /:id/splits`
stays for exact marks (a watch, offline batches); because the store keeps
the first mark of a segment and round, a timer that wants exact times
posts its marks before the progress save. Marks the segments do not allow
are dropped silently: a progress save never fails because of them.
