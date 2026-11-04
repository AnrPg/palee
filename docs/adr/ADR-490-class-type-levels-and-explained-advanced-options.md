# ADR-490: Class type levels as a multi-select, and explained advanced options
Date: 2026-11-04
Status: Accepted

## Context
In Ρυθμίσεις › Τύποι τμημάτων each class type card showed an «Εκδήλωση» checkbox
next to «Προχωρημένα», and inside «Προχωρημένα» a single-select «Επίπεδο» with
`beginner`, `all_levels` and `advanced` (Phase 2 plan §5a, ADR-197). ANR asked
(2026-11-04) for three changes:

1. «Εκδήλωση» is rarely used, so it belongs inside «Προχωρημένα».
2. «Επίπεδο» must allow several levels for one class type.
3. Every advanced option needs a detailed explanation, and a tooltip on hover.

A single `level` could not say "beginners and intermediate", and `all_levels`
mixed a level with the absence of one: a member who filtered by «Αρχάριοι» did
not see the many classes marked «Όλα τα επίπεδα», although they suit beginners.

## Decision
- **Data:** `class_types.levels text[]`, a subset of `beginner intermediate
  advanced` kept in that order; an empty list means «Όλα τα επίπεδα». The
  migration (`20270801100000`) backfills `beginner` and `advanced`; `all_levels`
  becomes the empty list. A check constraint holds the vocabulary.
- **API:** class types read and write `levels` (array, unique items) instead of
  `level`. The public box schedule returns `class_type.levels`.
- **Matching:** a class type suits a wanted level when its list is empty or
  contains that level. This one rule serves Πρόγραμμα's filter, the box page's
  filter, Γύρω μου (`palee_around_level_match`) and Partners suggestions (each
  class level admits the person levels it admitted before; none admits all).
- **Legacy value:** Γύρω μου ignores a sent `all_levels`, and the migration
  removes it from saved Γύρω μου filters, so older clients and saved alerts keep
  working.
- **UI:** «Εκδήλωση», «Επισκέψεις ανά κράτηση», «Επίπεδο» and «Κοινό» all sit under
  «Προχωρημένα». A card shows an «Εκδήλωση» badge next to the name while the
  section is closed, so the choice is never hidden. «Επίπεδο» is three toggle
  chips like «Κοινό», with «Όλα τα επίπεδα» shown when none is on. The settings
  catalog moves `class_type.kind` from basic to advanced.
- **Explanations:** `ExplainedSetting` (components/settings) puts an ⓘ next to
  each option's label. Hover or keyboard focus shows a one-sentence tooltip;
  a press opens an info box under the option with three parts: «Τι κάνει»,
  «Τι βλέπουν τα μέλη», «Πότε να το αλλάξεις». Touch screens have no hover
  (Tailwind 4 only applies hover on hover-capable devices), so a tap opens the
  info box directly. The old one-paragraph hint above the cards is removed.

## Rationale
An empty list for "all levels" matches how «Κοινό» already works (empty =
everyone) and makes "suits every level" a property of matching instead of a
fourth value people must pick. A text array with a check constraint keeps the
vocabulary in one place, needs no join table, and `&&` keeps the Γύρω μου query
a single indexed-friendly predicate.

## Alternatives Considered
- **Keep `all_levels` as a selectable value next to the levels:** two ways to say
  the same thing, and filters would have to treat it specially anyway.
- **A multi-select dropdown for «Επίπεδο»:** with three values, chips show the
  state at a glance and match «Κοινό»; a dropdown hides it behind a press.
- **Only a tooltip, no info box:** tooltips do not exist on phones and cannot
  hold an example; the info box carries the detail and the tooltip the gist.

## Consequences
- A filter for a level now also finds classes for all levels. In Γύρω μου most
  boxes have a general class type, so «Επίπεδο» narrows mainly by excluding boxes
  whose every class type targets other levels.
- `class_types.level` stays in the table, unused, so API pods of the previous
  release keep working during the rollout. TD-490 drops it later.

## Implementation Notes
- `Palee.Scheduling.ClassType.levels/0` is the vocabulary for the API, the
  OpenAPI enums and Γύρω μου; the web mirrors it as `CLASS_LEVELS` with
  `suitsLevels` and `classLevelsOf` in `api/schedule.ts`.
- New messages: `ClassTypeOptions.*`, `ExplainedSetting.about`,
  `BoxSchedule.level_intermediate` («Μεσαίοι»), in all 12 locales.
