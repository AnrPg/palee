# ADR-394: A Palee-wide board for benchmark WODs («Όλο το Palee»)
Date: 2026-11-03
Status: Accepted

## Context
ADR-356 left «Global scope is not built»: a box's WOD is the box's own copy, so comparing across
boxes needs a shared benchmark identity and consent to cross-box comparison. The product owner (ANR,
2026-11-03) picked option A of the mockup «Παγκόσμιος πίνακας κατάταξης»: a scope chip «Όλο το Palee»
on the same `#wod` leaderboard, shown only when the WOD is a known benchmark. Principle §4.4:
comparison with others is opt-in. Results live in tenant tables with forced RLS, which must not be
weakened.

## Decision
- **The coach tags the WOD.** `master_workouts.benchmark_key` (migration `20270516000000`), picked
  from a list in the WOD editor under «Προχωρημένα»; never guessed from the title.
  `GET /api/org/:slug/admin/workouts/benchmarks` lists the catalog, `PUT
  /api/org/:slug/admin/workouts/:id/benchmark` sets or clears it (`422 invalid_workout_benchmark`
  for an unknown key; `manage_workouts`). Copies keep the tag (a class variant of Fran is Fran).
- **The catalog** (`Workouts.Domain.WorkoutBenchmarks`) is the 23 anchored benchmarks of
  `Pantheon.Domain.FitnessBenchmarks` (ADR-358) plus ten leaderboard-only WODs the product owner
  added the same day: Annie, Jackie, Elizabeth, Nancy, Kelly, Angie, Barbara, Amanda, Murph and DT,
  all for time (lower is better), with English and Greek aliases. The ten have no fitness-profile
  anchors and never change the profile; `FitnessBenchmarks` stays the profile's own catalog. Murph
  with or without a vest is the scale level, not another benchmark. Each benchmark brings its unit
  and direction.
- **Only box results.** Executions and logged scores of a published, non-personal WOD of a box that
  carries the tag; not voided, not kept `private` (ADR-356). Self-logged personal workouts never
  count.
- **Consent, separate from the box opt-in.** `palee_leaderboard_consents` (account level, owner-only
  RLS): `share` (others see nickname, box name and score) or `see_only` (the person sees the board
  and their own rank and percentile; nobody else sees their row and it does not count for others).
  The first tap on «Όλο το Palee» asks once: «Να μπει το σκορ σου στον πίνακα όλου του Palee;» with
  «Ναι, να μπει» and «Μόνο να βλέπω τη θέση μου». `GET|PUT|DELETE /api/me/palee-leaderboard`; the
  same switch is in «Κοινοποίηση και ορατότητα». Withdrawing deletes the row, so the person leaves
  every board at once (boards are computed on read). In «Λήψη των δεδομένων μου» (section
  `training`); account deletion cascades, and an anonymised kept profile loses the row too.
- **Scope `palee`** on `GET /api/org/:slug/workouts/:id/leaderboard` (`Gamification.Domain.
  LeaderboardFilters`, `Application.PaleeBenchmarkLeaderboard`). It needs a tagged WOD (`422
  invalid_leaderboard_filter`, field `scope`) and an answer (`409 palee_leaderboard_consent_required`);
  buddies do not apply (`422`, field `buddies`). Division, age group, scale and time window work as in
  ADR-356; division and age group come from the person's opt-in row at the box where the result was
  logged. The response carries `benchmark` and the viewer's `palee_consent` for every benchmark WOD;
  rows add `box_name`, and on the Palee board `user_id` is null and `avatar_url` empty for everyone
  but the viewer. Percentiles need five results (ADR-356).
- **The one cross-box read** is two narrow `SECURITY DEFINER` functions, like `palee_around_*`
  (ADR-154): `palee_benchmark_results(key, from, to, year)` returns per consented result an opaque
  person reference (md5 of account and benchmark), whether it is the caller, nickname, box name, WOD
  id, scale level, division, age group (reckoned in SQL; no birth year leaves) and the section scores;
  `palee_benchmark_workout_sections(key, ids)` returns which sections of those WODs are scored. Both
  answer nothing without `app.user_id`, and pin only `search_path`. RLS on every tenant table is
  unchanged.
- **Ranking.** Each WOD is read by its own scored section (`WorkoutDayLeaderboard.ranked_section`,
  the box board's rule); a result counts only when the section's direction matches the benchmark's
  (a Fran scored in reps does not mix in). Each person counts once, with their best result.

## Rationale
A coach's tag is the only reliable shared identity: titles vary («Fran», «FRAN 21-15-9», «Φραν»)
and guessing would rank different WODs together. Separate consent keeps §4.4: being on one box's board
never means being shown to strangers. Two functions that answer one question each keep the blast
radius of the cross-box read small and leave tenant RLS untouched.

## Alternatives Considered
- A shared platform table of benchmark scores written on every result: needs hooks on every write,
  edit, void and visibility change, and goes stale; computing on read keeps one source of truth.
- Matching WOD titles to the catalog (as the fitness profile does for PR names): ranks different
  workouts together; refused by the product owner.
- Option B (a «Palee Benchmarks» club) and C (only a percentile, no names): not picked.
- Reusing the box opt-in as consent: the product owner asked for a separate one.

## Consequences
- The board reads every tagged result of the window on each request; fine at pilot scale, a cache or
  materialised slice may be needed later (open question).
- Boxes name their scale levels; the scale chip compares slugs (`rx`, `scaled`), which the default
  levels share.
- A WOD scored as rounds+reps in one box and reps in another (Cindy) is ranked on each section's own
  scale; mixing those two forms is an open question.

## Implementation Notes
- The web picks «Όλο το Palee» with the window «Όλα» (all time); the window stays changeable under
  «Προχωρημένα».
- The «Όλα» window reads from 2000-01-01, as the box board does.
