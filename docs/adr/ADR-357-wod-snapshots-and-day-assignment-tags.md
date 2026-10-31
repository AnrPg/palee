# ADR-357: WOD snapshots when assigned or performed, and day assignment tags
Date: 2026-10-31
Status: Accepted

## Context
CP-D3: Kilo tags programming days «Not Assigned / Mixed / All Assigned» and freezes a WOD when it is
assigned. In Palee a class gets its own copy of a template (ADR-230 `ClassWorkoutFiling`), so editing
the template never changed a class's WOD; but an athlete assignment (`assigned_workouts`) points at
its workout directly in the direct and class-variant paths, and the class's copy can be reopened and
edited after people logged scores against it, silently rewriting what they performed. The programming
calendar showed day WODs but not whether every class of a day had one.

## Decision
- **`workout_snapshots`** (tenant table, forced RLS, migration `20270505000100`): content-addressed
  (`content_hash` = SHA-256 of the canonical content, unique per box and WOD), `format_version`,
  `title`, `content` (what the WOD says: title, type, text, sections with their ids, plans,
  exercises, body; never folder, status or timestamps — `Workouts.Domain.WorkoutSnapshot`). No foreign
  key to the WOD: a snapshot outlives it.
- **Who points at one**: `assigned_workouts.workout_snapshot_id` (written after an assignment is
  created, `AssignWorkout`), `workout_executions.workout_snapshot_id` (on completion,
  `CompleteWorkout`), `training_log_entries.workout_snapshot_id` (when a score is logged,
  `LogTrainingEntry`). `Application.WorkoutSnapshots.capture_for/4` never fails the write it follows:
  a missing snapshot is logged.
- **`GET /api/org/:slug/workout-snapshots/:id`**: staff with `manage_workouts` or
  `view_client_training`, or the person whose own assignment, run or score points at it (else 404).
- **Day tags**: `GET /admin/schedule/day-workouts` gains `days: [{date, tag, classes, with_wod}]`, tag
  `none | not_assigned | mixed | all_assigned` over the live classes the caller may see
  (`Scheduling.Domain.DayAssignmentTag`; cancelled classes do not count).

## Rationale
Content addressing stores one row per distinct content however often a WOD is used, and makes «did
it change?» a hash comparison. Hooking the three application services that create the holders keeps
the Execution and Workouts stores unchanged.

## Alternatives Considered
- Freezing every class's WOD at link time: a coach fixing a typo before class must update it; the
  class's copy already shields it from the template.
- Making WODs immutable once used: blocks legitimate fixes and the day-WOD flow.

## Consequences
- Older results have no snapshot (`nil`); the screens show the live WOD for them.
- Section and exercise ids are part of the content, so a save that rewrites exercise rows gives a new
  snapshot even with the same words. Harmless (a few rows), noted.
- Tenant purge removes snapshots after `assigned_workouts` (Workouts `TenantDataPolicy`).
