# ADR-549: Παραίτηση in time-set sections
Date: 2026-11-04
Status: Accepted

## Context
ANR (2026-11-04): in AMRAP-like sections (the clock is set, the score is the
work done: rounds, reps, kcal, metres) there is no way to tell that an
athlete gave up mid-way. Until now the only signal was an execution that was
never completed, swept as `workout_execution_abandoned` after 6 hours
(ADR-123). «Τέλος προπόνησης» in the middle of an AMRAP counted as a normal
completion, and nothing compared the time run with the section's length. An
athlete who sits idle while the clock runs out leaves no trace at all. The
client interaction pipeline (ADR-123, `lib/execution-analytics.ts`) existed
but was never wired into the timer.

## Decision
- **Time-set section** (`Execution.Domain.Retirement.time_set_sections/1`),
  read from the server's own timer segments, so legacy formats, text
  presets and structured plans (`PlanTimer`) all qualify the same way: every
  work segment has a fixed length (countdowns, interval cycles with a set
  number of windows), and the section is not scored by time. Count-ups
  (For Time, ladders, kcal targets) and open-ended windows (Death By, EMOM to
  failure) never qualify: stopping is how they end.
- **Work taps** (`kpi_counters.activity`): the device records the section's
  active time (ms) of each tap that records work: a round done or an
  exercise checked (classic timer, `recordWorkTap`), a plan step marked done
  (plan runner, `RunState.workTaps`). A check that finishes a round counts
  once. They travel with the existing progress and completion payloads;
  `Retirement.merge_activity/3` keeps time-set sections only, valid times
  only, at most 300 per section, and only accumulates (offline replays never
  remove one).
- **Verdict at completion** (`Retirement.assess/3`), stored in
  `kpi_counters.retirement` so every reader (KPI report, analytics events,
  later Πρόοδος or leaderboards) takes the same one:
  `stopped_early` (ran less than the adjusted length, beyond a 1 s clock
  tolerance; a section never reached included), `shortened` (took time off
  the clock with «−30 s» and ran the rest), `idle` (after the last work tap
  the clock ran on for more than `retirement_idle_factor` × the athlete's own
  median time between taps; needs 2 taps for a pace), `unknown` (too few taps
  to tell), `full`. `stopped_early` and `idle` are Παραίτηση.
- `config :palee, :retirement_idle_factor, 3` (ANR's decision card,
  recommended option); nil keeps the facts without the `idle` verdict.
- `workout_execution_completed` carries the flat facts (`retirement_verdict`,
  `time_set_section_count`, `retired_section_count`, `stopped_early_ms`,
  `idle_tail_ms`). The KPI report adds `retirement`: counts per verdict,
  `retired_rate`, medians and `by_format`, over completed executions (an
  execution never completed stays an unfinished workout, not a retirement).
- **Interactions wired** (`hooks/useExecutionInteractions.ts`): the classic
  timer now sends `pause`, `resume`, `segment_skipped`, `round_incremented`,
  `round_decremented`, `time_adjusted`, `finish_wizard_opened`,
  `finish_wizard_saved`, plus the new **`timer_closed`** (position, segment
  time, clock left) when the athlete leaves an unfinished workout (page hide
  or screen left), sent with `keepalive` so it survives the tab closing.

### Follow-up (2026-11-04, ANR picked 1Α, 2Β, 3Β from the mockups)
- **3Β, the athlete's answer.** When a time-set section ran short of its clock
  (as run, after «±30 s»), the «Τέλος προπόνησης» confirm step shows one quiet,
  optional question per section: «Σταμάτησες στο 6:00 από 10:00.» with chips
  «Σταμάτησα νωρίτερα» / «Ήθελα μικρότερο WOD» (`StoppedEarlyQuestion`, both
  the classic timer and the plan runner; `lib/retirement.ts` and
  `plan/sequence.ts timeSetMs/2` mirror the server's time-set rule).
  `PATCH /executions/:id/complete` takes `retirement_answers`
  (`{section_id: "gave_up" | "chose_shorter"}`). On a `stopped_early` section
  only: `chose_shorter` makes it `shortened` («Μίκρυνε τον χρόνο», not
  Παραίτηση), `gave_up` confirms it; the answer is kept as `answer`.
  Unanswered, the verdict stays `stopped_early`.
- **1Α, staff Στατιστικά.** One «Παραίτηση» card in the execution KPIs: the
  rate over time-set sections of completed runs, «Σταμάτησαν πριν τη λήξη» /
  «Έμειναν ανενεργοί», and the rate per Ροή; details in «?».
- **2Β, a neutral fact.** `part_of_time` (`{ran_ms, planned_ms}` of the first
  section run short, `stopped_early` or `shortened`) on the athlete's own
  history entries (gym and account) reads «Έτρεξε 6:00 από 10:00». Leaderboard
  rows (workout, day WOD, today card) carry it too and show only a small time
  mark («6:00», the sentence on hover / screen reader). The word Παραίτηση is
  never shown to anyone but staff.
- **Closing the timer counts sooner.** `timer_closed` is stored on the
  unfinished execution (`kpi_counters.closed`: position, segment time, clock
  left, `at`). The abandonment sweep also records a run as unfinished once
  `config :palee, :execution_abandonment_after_close_minutes` (60) have
  passed since the close with no progress after it, instead of waiting for
  the 6 h threshold. The abandonment event adds `closed_by_athlete`,
  `closed_segment_index`, `closed_elapsed_ms`, `closed_remaining_ms`,
  `minutes_since_close`. nil turns it off.
- **Exact round times.** The classic timer keeps a `round_marks` list (segment
  key, round, clock ms at the tap; last 100) and sends it with progress
  (max 500). Split marks (ADR-374) take a round's time from its mark when one
  exists (round ≥ 1, 0 ≤ ms ≤ the save's clock, known segment), else the
  save's time as before.
- **The plan runner's interactions.** `pause`, `resume`, `finish_wizard_opened`,
  `finish_wizard_saved` and `timer_closed` (section, elapsed, clock left on a
  time-set section) are now sent from the structured plan runner too
  (`useExecutionInteractions` takes the runner's own close position).

## Rationale
The time run against the length is exact and needs no guess. Idle detection
compares the athlete with themselves, never with a fixed number of minutes,
so a slow athlete is not a quitter and a fast one sitting for 3 minutes is
caught. Storing the verdict once, next to the execution, keeps the
analytics, progress and leaderboard readers from re-deriving it differently.
No migration: `kpi_counters` already holds device-observed facts and the
server's own derived facts (`position`, `formats`).

## Alternatives Considered
- A fixed idle threshold in minutes: wrong for a 5' and a 30' AMRAP alike.
- Deriving taps from split marks (ADR-374): they carry the progress save's
  time, so rounds saved together share one time, and checks are not marks.
- A list of reasons (fatigue, pain, time…): richer, but too many choices for
  a tired athlete (mockup 3Γ). Not asking at all (3Α) loses the why.
- Ranking short runs below full ones (2Γ): fairer but harsher; not chosen.

## Consequences
- An athlete who never taps (types only the score) is `unknown`, never
  retired. EMOM windows advance on their own, so they are known only through
  checks.
- The plan runner's work taps reach the server at completion (it has no
  store progress); its interactions are sent live.
- An answer from an old client is simply absent: the verdict stands as
  measured.
