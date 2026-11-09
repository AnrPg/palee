# ADR-571: Text-section timer chips: the coach's three most used timers, «Χωρίς χρόνο» by default
Date: 2026-11-09
Status: Accepted

## Context
In the text-section editor (ADR-180, WOD assistant off) every section needed a timer before publishing, and the timer panel showed seven fixed chips (Tabata, EMOM 10, E2MOM 20, AMRAP 12, For time cap 12, Death By, Stopwatch). ANR (2026-11-09): add «Χωρίς χρόνο» as a chip and in the dropdown; keep only three chips plus «Χωρίς χρόνο» plus the dropdown; «Χωρίς χρόνο» is the default, so a section always has a timer; the three chips are the ones this author uses most (e.g. EMOM 4, AMRAP 10, AMRAP 20) and change as they write. Then: the dropdown has another colour and shows its arrow.

## Decision
- **Default.** A section's timer is «Χωρίς χρόνο» (`{format: "untimed"}`) until the coach picks another. The editor creates sections with it; the API treats a missing `timer_preset` the same way (`SectionedText`), so publishing never fails for a missing timer. `timer_required` now only means "a timer that is not a known preset".
- **Chips.** `GET /admin/workouts/frequent-timers` answers up to three presets, most used first, each with `source` (`author`, `gym`, `stock`) and `uses`. The domain (`Workouts.Domain.FrequentTimerPresets`) counts the acting coach's published workouts (text sections' timers and a free-text workout's attached timer), tops up with the gym's most used, then with stock ones, never repeating a timer and never counting «Χωρίς χρόνο» (always its own chip). Ties go to the timer used last.
- **Same timer, one chip.** Presets compare by their canonical form: only the fields the format runs on, with the timer engine's values for missing ones. The web (`canonicalTimerPreset`) and the API (`canonical/1`) check one shared fixture, `apps/web/src/lib/timer-preset-canonical-fixtures.json`.
- **Chip names** the way coaches say them: «AMRAP 10», «EMOM 4», «E2MOM 20», «For Time 12′», «Tabata 20/10 × 8» (`timerChipLabel`).
- **Row.** Three chips, «Χωρίς χρόνο», then the format dropdown (every format, «Χωρίς χρόνο» included) in Deep (`--deep`, `--deep-contrast`) with its chevron, so it reads as the menu and not as one more chip; a format picked there that matches no chip gets a Dojo ring. The section's timer button also shows a chevron. The numbers of the chosen format follow underneath (`FreeTextTimerFields`, `showFormat={false}`).
- The query uses `FRESHNESS.reference` and is invalidated after a publish, so the chips follow the coach's newest WODs.

## Rationale
The coach's own history answers "which three" without Palee choosing for them (no-arbitrary-defaults rule). The API owns the count, so the chips are the same on every device; the pure domain module keeps the rule testable apart from the query.

## Alternatives Considered
- Counting in the browser (localStorage): differs per device and is lost on a new phone.
- Counting drafts too: a half-written draft is not use.
- Stock fallback chosen by Palee for a coach and gym with no history: needed so the row is never empty. Chosen: AMRAP 12, EMOM 10, For Time cap 12 (the three most common CrossFit formats, at the lengths the timer engine already uses when none is given). A gym's own history replaces them as soon as anyone publishes.

## Consequences
- Old drafts with `timer_preset: null` now publish as «Χωρίς χρόνο» instead of asking for a timer.
- The assistant's free-text editor (timer tab with «Επισύναψη χρονομέτρου») is unchanged; it can reuse `TimerChips` later.

## Implementation Notes
- `EctoWorkoutStore.timer_preset_usage/1` groups by the stored jsonb preset; the domain merges rows that are the same timer written differently.
- EN `timerNoTime` is «No time»; the other locales reuse their `formatLabel_untimed` wording.
