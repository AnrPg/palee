# ADR-650: WOD formats while typing and the timer from the text

Status: Accepted (ANR, 2026-11-16)
Builds on: ADR-270 (structured flows and presets), ADR-570 (suggestions at the caret), ADR-571 (text-section timer chips)

## Context

Coaches write the format of a text WOD on its first line («AMRAP 12»,
«E2MOM 20», «Tabata», «For time, cap 15»), and then set the same timer again
by hand: in the free-text editor in the «Χρονόμετρο» tab, in a text section
with its chips. ANR asked (2026-11-16) for the formats in the suggestion list
and for the timer to be set from the text when it reads correctly, always
editable before publishing. Picks from the mockups
(`/mnt/project-files/milos/free-text-timer-suggest/`): A1 B1 Γ1 Δ1 Ε1 Ζ1.
ANR also asked for as many of the existing formats as possible, a canonical
list of them, and additive changes.

## Decision

- **Canonical list** (`apps/web/src/lib/wod-formats/catalog.ts`,
  `WOD_FORMATS`): built from the structured editor's six flows and seventeen
  presets, so names, aliases and agreed values (Tabata 20″/10″ × 8, Billat
  30″/30″ × 10, HRR 3:00 × 3, EDT 15′, Death by every 1:00) have one source.
  Each format says which free-text timer it runs, or none (sets,
  structures, rest, add-ons are offered but never set a timer). The readable
  table is `docs/product/wod-formats.md`; a test keeps it in step.
- **Parser** (`wod-formats/parse.ts`): a format counts only at the start of a
  line (after a bullet, «B)», or a short «Part B:» label), so exercise lines
  never set a timer. Bare numbers are minutes after AMRAP, EMOM and a cap,
  seconds in a work/rest pair. A name missing its number («AMRAP») sets
  nothing and says what to add. Formats written as the timer chips write
  them read back to the same timer.
- **Suggestions (Δ1)**: the ADR-570 list gets the formats on top, labelled
  «Μορφή», the coach's most used timers first («Μορφή · συχνό σου», ADR-571
  endpoint). Same keys (Tab, ↑/↓ + Enter, Esc) and ghost completion. Unlike
  exercises they come from the browser (no server search), are offered only
  at the start of a line, link nothing in the document and are never asked
  about as exercises.
- **Timer from the text (A1, Γ1)**: while the timer follows the text it is
  the text's first timer, shown as a green chip «… · από το κείμενο» with
  «Αλλαγή». Any change by hand makes it the coach's own; the text no longer
  changes it until «Από το κείμενο». Nothing about the source is stored: a
  saved timer reads back as following the text when the text asks for it,
  so drafts saved before this ADR keep the timer they had.
- **Several formats in one free text (B1)**: the first sets the timer;
  «βρέθηκαν 2» with «Το επόμενο», and a note to split the WOD into sections
  for one timer each.
- **Publishing (Ε1)**: a timer that came from the text and was never touched
  gets a row «Χρονόμετρο από το κείμενο: AMRAP 12 · Ναι / Αλλαγή» in the
  ADR-570 dialog; the dialog opens for it even when no exercise was found.
- **Text sections (Ζ1)**: each section's text picks its own chip, with the
  same rules; the timer button turns green with «· από το κείμενο».
  Sections have no publish dialog, so no Ε1 row there.

## Consequences

- Web only: the API stores the timer the editor sends, as before
  (`workout_metadata.free_text_timer`, a section's `timer_preset`).
- Formats are read in all twelve languages Palee speaks, all at once (a WOD
  reads the same for every viewer, and coaches mix English in): the
  structured editor's translated names plus each language's words for
  rounds, «every», time cap, work/rest and units (`wod-formats/locale-words.ts`;
  a test keeps its names equal to the messages). A suggestion always inserts
  a name the parser reads back.
- A new flow or preset in the structured catalog appears in the list; its
  timer mapping must be added in `catalog.ts` (the test lists them all).
