# ADR-671: Every exercise counts before publishing, whichever editor wrote it

Status: Accepted (ANR, 2026-11-21)
Builds on: ADR-163 (WOD goals), ADR-180 (sections without the assistant), ADR-570 (exercise suggestions and confirmation)

## Context

ANR asked whether a WOD's muscles and qualities are computed only for the
suggestions the coach clicked. They are not: the live suggestion reads the
whole text (exact names, aliases and plurals), and the free-text editor asks
about every other match before publishing (ADR-570). Three gaps remained:

1. The editor with sections (assistant off) had no check before publishing:
   a misspelt exercise («Thrustr») was silently left out, and a name picked
   from the suggestions stayed plain text.
2. Goals the coach edited by hand grew only when the check dialog was
   answered. Exercises linked from the suggestions (no dialog) never reached
   them; and the dialog merged the whole suggestion, so a muscle the coach had
   removed came back.
3. If the check request failed, publishing went on without a word.

## Decision

- **Sections are checked too.** `GET …/exercise-matches` reads a sectioned
  draft section by section; each match carries `section` (0-based, the
  draft's order) and its line in that section's document. The sectioned
  editor shows the same «Αναγνωρίσαμε ασκήσεις» dialog, puts the answers into
  each section's document as `exerciseLink` marks (`linkSections`,
  `linkSectionDocument`) and only then publishes. The section editor now has
  the `exerciseLink` mark, so a picked suggestion is linked as in the
  free-text editor.
- **Edited goals grow by what is new, on every publish.**
  `workout_goals.suggestion_basis` stores the suggestion the edited goals were
  last reconciled with (set on every staff save of the goals).
  `GrowEditedGoals` folds in only what the suggestion gained since that basis
  (`GoalSuggestion.gained/2`: muscles new or with a stronger role, qualities
  new), upwards only (`merge_up/2`), then moves the basis. It runs on every
  publish (`PublishWorkout`, any editor, with or without the dialog) and after
  the dialog is answered. A muscle the coach removed is in the basis, so it is
  never put back; a coach's own demotion stays. Goals saved before ADR-671 have
  no basis: the published text's suggestion stands in once (nothing for a
  first publish). A failure here never fails the publish.
- **A failed check is said.** Both editors show «Δεν ελέγχθηκαν οι ασκήσεις…»
  with «Δοκίμασε ξανά» and «Δημοσίευση χωρίς έλεγχο» (12 languages).
- **The suggestion list stays under the line being written.** It no longer
  flips above the line when the room below is short; it keeps at least
  120 px and scrolls inside (also under a phone keyboard, `visualViewport`).

## Consequences

- Migration `20271121100000_workout_goals_suggestion_basis` (nullable `map`).
- The OpenAPI `ExerciseMatch` gains nullable `section`; `id` is
  `[section:]line:from:to`.
- Tests: `exercise_check_sections_test.exs`, the ADR-570 controller test
  (quadriceps keeps the coach's stabilizer), `SectionedWorkoutEditor.links.test.ts`,
  `EditorExerciseSuggestions.test.tsx`, e2e `sectioned-exercise-check.spec.ts`.
