# WOD formats: the canonical list

Source of truth in code: `apps/web/src/lib/wod-formats/catalog.ts` (`WOD_FORMATS`, ADR-650),
built from the structured editor's flows and presets (`apps/web/src/lib/structured-plan/catalog.ts`, ADR-270).
Display names follow `docs/product/ontology.md` (Flow «Ροή», Preset «Έτοιμη μορφή»): AMRAP, EMOM, For Time,
Tabata stay untranslated. `catalog.test` checks that every key below exists in code and the other way round.

The text editors (free text and text sections) offer every format while a coach types the start of a line,
and set the timer for the ones that are a clock. A format is read only at the start of a line.
Coaches see this list as the help «Πώς γράφω το χρονόμετρο;» in the editors (plain steps and examples, no table).
Bare numbers: minutes after AMRAP, EMOM and a time cap; seconds in a work/rest pair.
Every language Palee speaks is read (German «Auf Zeit, Zeitlimit 15», French «toutes les 2 min x 5», Russian «Каждую минуту 10», …): the translated names of the structured editor plus each language's words for rounds, «every», cap and units (`apps/web/src/lib/wod-formats/locale-words.ts`).

## Flows (how the clock runs)

| Key | Name | Written as (examples) | Timer it sets |
| --- | --- | --- | --- |
| `sets` | Σετ / Sets | Strength, Δύναμη, Sets, Hypertrophy | none |
| `for_time` | For Time | For time · FT · RFT · 5 RFT · 3 rounds for time · Για χρόνο · For time, cap 15 · FT (TC 12') · Για χρόνο, όριο 20' | For Time, with the cap when written |
| `amrap` | AMRAP | AMRAP 12 · 12' AMRAP · AMRAP in 20 minutes · Όσους γύρους 15' · AMRAP 7:30 | AMRAP of that length (needs the minutes) |
| `emom` | EMOM | EMOM 10 · EMOM x 12 · E2MOM 20 · E3MOM x 5 · E90S x 8 · Every 2' x 6 · Every 1:30 for 12' · Κάθε 3' x 5 · 20 min EMOM · EMOM 8 × 1:30 | EMOM, interval × rounds (needs a number) |
| `intervals` | Intervals | 40/20 x 8 · 30 on 30 off x 10 · Intervals 1:00/1:00 x 5 · HIIT · Διαστήματα | Intervals, work/rest × rounds (needs them); 20/10 is Tabata |
| `rest` | Ξεκούραση / Rest | Rest, Ξεκούραση | none |

## Presets (known names that fill a flow)

| Key | Name | Written as (examples) | Timer it sets |
| --- | --- | --- | --- |
| `tabata` | Tabata | Tabata · Tabata x 6 · Tabata 20/10 × 8 | Tabata 20″/10″ × 8 (rounds as written) |
| `billat` | Billat | Billat · Billat x 12 | Intervals 30″/30″ × 10 |
| `hrr` | Ανάκαμψη παλμών (HRR) | HRR, Heart rate recovery | Intervals 3:00 × 3 |
| `death_by` | Death by | Death by burpees · Death by thrusters every 2' | Death by, every 1:00 (or as written) |
| `even_odd` | Εναλλάξ (μονά / ζυγά) | Alternating EMOM 12 · Even odd 10 · Μονά ζυγά 12 | EMOM (needs a number) |
| `complex_emom` | Complex EMOM | Complex EMOM 15 | EMOM (needs a number) |
| `edt` | EDT | EDT · EDT 20 | AMRAP 15′ (or as written) |
| `chipper` | Chipper | Chipper · Chipper, cap 30 | For Time |
| `21_15_9` | 21-15-9 | 21-15-9 · 21 - 15 - 9 thrusters & pull-ups · Fran | For Time |
| `ladder` | Σκάλα / πυραμίδα | Ladder · Pyramid · Σκάλα · Πυραμίδα | For Time |
| `calorie_target` | Στόχος θερμίδων | Calorie target · Στόχος θερμίδων | For Time |
| `to_failure` | Μέχρι αποτυχία | To failure · Μέχρι αποτυχία | none |
| `superset` | Superset / γιγάντιο σετ | Superset · Giant set | none |
| `cluster` | Cluster | Cluster | none |
| `drop_set` | Drop set | Drop set | none |
| `rest_pause` | Rest-pause | Rest-pause · Myo reps | none |
| `interrupt` | Με διακοπή | Interrupt every · Διακοπή · Παρεμβολή | none |

## Not read as a format

Lines that only start like one, on purpose: «Target: …», «Calories …», «Rest 1:00 between rounds» (rest sets
no timer), «50 cal row», «Back squat 5x5», «Death by 10m shuttle» (reads Death by every 1:00, the distance is
not a time). A name without its number («AMRAP», «EMOM») sets nothing; the editor says what to add.
