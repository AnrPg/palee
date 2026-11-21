# ADR-680: A WOD made for one thing lives only in that thing's folder

Status: Accepted (ANR, 2026-11-21)
Builds on: ADR-125 (member programming), ADR-163 (WOD goals), ADR-176 (class without WOD), ADR-230 (day WODs)

## Context

«+ Νέο WOD» inside a day («WOD ημέρας»), a class, the athletes' assignment or
a member's programming created the WOD at the library root. Assigning it then
filed it like any library template: a *copy* went into the day's, class's or
athlete's folder and the original stayed at the root. ANR saw every such WOD
twice in the Αρχείο WOD (e.g. «Strength · CrossFit» at «Αρχή βιβλιοθήκης» and
in `Τμήματα/<date>`). Only member programming (`copy_source: false`) already
moved the original. A class created together with its new WOD filed nothing,
so that WOD stayed only at the root.

## Decision

- **Domain flag** `master_workouts.awaiting_filing`: the WOD was made for one
  thing. Set at creation (`POST /admin/workouts {awaiting_filing: true}`); the
  web sets it for every draft started under `NewWorkoutForAssignment`
  (`ContextualWorkoutCreator`, the athletes' `QuickAssignModal`).
- **One rule, one place**: `FileWorkoutCopy.ensure_in_folder/4`, which every
  filing goes through (day WOD, class link/edit, athletes, class programming),
  *moves* an awaiting WOD into the target folder and clears the flag, keeping
  its id. Later filings of it copy, as for any template (e.g. a second athlete
  or another day). `discard/3` puts a moved WOD back, still awaiting, when the
  step it was filed for fails.
- **New class**: creating a class still files nothing, except a WOD awaiting
  filing, which moves into the class's day folder
  (`ClassWorkoutFiling.with_class_made_workout/3`).
- **Member programming** keeps moving the original and now clears the flag.
- **By hand**: moving a WOD in the library (`PATCH /admin/workouts/:id/library`)
  clears the flag; the coach filed it. That endpoint now takes only `folder_id`.
- A WOD the coach never assigns stays at the root, still awaiting, and moves
  the first time it is assigned.
- Recurring series are not dated, so a new series's WOD is not filed.

## Consequences

- No more root duplicates for new WODs; goals stay on the WOD itself.
- Existing duplicates (ANR chose «Αυτόματο καθάρισμα»): migration
  `20271121110000` removes a root WOD only when it is a published shared
  non-benchmark, has exactly one copy, that copy is in a day/athlete/member
  system folder, was made within a day after it, it was not edited after the
  copy, and nothing else uses it (classes, series, day WODs, assignments,
  logs, executions, snapshots, plan sets, scaling suggestions, programmes).
  Its goals move to the copy first. A one-day-old template used exactly once
  this way looks the same and is removed too; its copy keeps everything.
