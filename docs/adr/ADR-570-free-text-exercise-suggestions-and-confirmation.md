# ADR-570: Exercise suggestions in the free-text editor and confirmation before publishing

Status: Accepted (2026-11-09)

## Context

Free-text WODs feed muscles and qualities (ADR-163, ADR-560) only through a
silent parser. ANR asked (2026-11-09) for code-editor style suggestions while
typing, to steer coaches to canonical exercises, and for a mandatory yes/no on
every exercise the parser finds before publishing (accept all / reject all;
nothing found is fine; optimistic).

## Decision

- **Links in the document.** A TipTap mark `exerciseLink {ref, checked}` ties
  words to a catalog exercise. `ref: null` is a «Όχι»: the words stay plain
  text (orange-red highlight, never strikethrough), are not counted and not
  asked again in that WOD. Letters typed against a link join it, so a link
  disappears only when all its words are deleted. When a link's words no
  longer resolve to its exercise, the check asks once «Ακόμα X;» (`checked`
  stores the confirmed folded words). No per-WOD table.
- **Suggestions at the caret.** `/me/exercise-suggestions` (Meilisearch),
  Palee's names first, then the box's, then mine, each labelled; grey ghost
  completion of the selected name. Tab always accepts; Enter accepts only
  after ↑/↓, otherwise it is a new line; Esc hides the list until it changes;
  tap picks. A catalog name sets the link.
- **Matcher** (`Workouts.Domain.ExerciseMatcher`): runs of up to four words,
  exact after folding, reordered word bags, then fuzzy: Greek transliterated,
  spelling variants folded (ph/f, ck/k, y/i, doubled letters, plural s), OSA
  Damerau-Levenshtein with a length-based budget (1 from 4 letters, 2 from 6,
  3 from 10) after a bigram prefilter. Always asks, never decides.
- **API**: `GET /api/org/:slug/admin/workouts/:id/exercise-matches` lists
  unlinked matches (and changed links) of the saved draft;
  `POST …/exercise-matches/decisions` records the answers.
- **Box memory**: `exercise_match_memories (organization_id, folded,
  exercise_ref)`, tenant RLS. A «Ναι» is remembered (offered pre-answered
  next time, still changeable); a «Όχι» to a remembered match forgets it.
- **Edited goals only grow**: if the coach edited the goals, the new
  suggestion may add muscles or promote roles (stabilizer → secondary/primary,
  secondary → primary), never downgrade or remove (`Anatomy.merge_goals_up/2`).
- Linked spans count with their line's sets weight in
  `FreeTextExercises.from_lines/1`; unlinked text keeps the old parser.
- Only new publishes are affected.

## Consequences

The publish dialog appears only when something was found. If the check is
unavailable, publishing proceeds (optimistic).
