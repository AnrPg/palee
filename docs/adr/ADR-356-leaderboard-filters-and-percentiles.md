# ADR-356: WOD leaderboard filters and a percentile per score
Date: 2026-10-31
Status: Accepted

## Context
CP-D2 (backlog `docs/plans/competitive-parity-and-beyond.md`): Kilo and Wodify let people filter a
WOD's leaderboard by gender, age group, level and date, and tell them their percentile. Palee ranked
one WOD per gym day (`WorkoutDayLeaderboard`, ADR-138 D6) for the `#wod` card and the box screen,
with no filters. Palee stored neither a gender nor a birth date anywhere a leaderboard could read
(only the partners profile keeps a gender, which never leaves it). Principle §4.4: comparison is
shown only to people who chose leaderboards; self comparison stays in the Journal.

## Decision
- **The person tells the box, optionally.** `leaderboard_opt_ins` (a tenant row per box, deleted on
  opt-out) gains `division` (`women`, `men`, or nothing) and `birth_year` (migration
  `20270505000000`). `GET|PUT /api/org/:slug/me/leaderboard-profile`; `PUT` before opting in is
  `409 leaderboard_not_opted_in`. Only the birth year is kept (data minimisation): masters-style age
  groups use the age reached during the year (`under_18`, `18_34`, `35_39` … `60_64`, `65_plus`).
- **`GET /api/org/:slug/workouts/:id/leaderboard`** (`GetWorkoutLeaderboard`) with filters
  `division`, `age_group`, `scale` (a scale level slug), `scope` (`box` or `branch` + `location_id`,
  the person's home branch), `window` (`day`, `week`, `month`, `year`, `all` around the gym `date`),
  `buddies`. Pure rules in `Gamification.Domain.LeaderboardFilters`; a filter that does not read is
  `422 invalid_leaderboard_filter` with its `field`.
- **Percentile** (`Gamification.Domain.ScorePercentile`): `percentile` = share of the other results
  of the slice this one beat; `top_percent` = share at this place or better, rounded up («στο top
  20%»). Nil below five results.
- **Who sees what.** Results kept `private` never rank. Only opted-in people rank. A viewer who did
  not opt in gets `opted_in: false`, no rows, and only their own result without rank or percentile.
- **Global scope is not built.** A box's WOD is the box's own copy; comparing across boxes needs a
  shared benchmark identity (CP-D4 marketplace / library) and consent to cross-box comparison. Left
  as an open question for the product owner.

## Rationale
The opt-in row is the one place that already means «compare me»; putting division and birth year on
it ties them to that consent and deletes them with it. Computing on read over one WOD's results
keeps one source of truth (results can be voided or edited).

## Alternatives Considered
- Gender and birth date on the account: personal data far beyond what a leaderboard needs.
- A materialized ranking table: stale on every edit or void; WOD result sets are small.
- Percentile from three results: says more about who came, and lets anyone work out places.

## Consequences
- People without a division appear only when no division filter is chosen.
- `leaderboard_opt_ins` is now in «Λήψη των δεδομένων μου» (ADR-267, section `training`); it was
  missing before. Account deletion already cascades.
- The web screens wait for the product owner's pick among the mockups
  (`v31-mockups/w5-training.html`).

## Implementation Notes
Branch filter reads each opted-in person's membership home branch; buddies are open buddy links.
