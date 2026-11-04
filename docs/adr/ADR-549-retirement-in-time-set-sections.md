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
- Asking the athlete in the finish wizard («Σταμάτησες πριν τελειώσει ο
  χρόνος;»): the most certain answer, but a UX change; mockups first.

## Consequences
- An athlete who never taps (types only the score) is `unknown`, never
  retired. EMOM windows advance on their own, so they are known only through
  checks.
- The plan runner does not send interaction events yet (it has no store
  progress); its work taps reach the server at completion.
- Where Παραίτηση shows (staff Στατιστικά, the athlete's Πρόοδος,
  leaderboards) waits for mockups (W-rule: mockups before UX builds).
