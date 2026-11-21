# ADR-690: A box adds its own workout types, and a WOD has several types
Date: 2026-11-21
Status: Accepted

## Context
ADR-275 made «Τύπος προπόνησης» one fixed Palee list (45 kinds in 9
families) from which a box only hides kinds. ANR (2026-11-21) asked for two
things the fixed list cannot do:

1. A WOD author adds a type that is missing. It joins the box's own list at
   once and reaches the Palee team, who may add it for everyone.
2. A WOD can have several types (a strength part and a metcon, HYROX that is
   also functional training).

Mockup: `milos/workout-types-custom-multi/workout-types-custom-multi-mockups-2026-11-21.html`.
ANR's picks: 1A (a box type always belongs to a family), any WOD author
creates one, «Μήπως εννοείς…» before creating, the owner manages box types
in Settings › «Τύποι προπόνησης» (rename, family, merge, hide), a box type
reads as typed in every language, the Palee team learns through a console
queue plus one digest email a day (only on days with news), a name enters
the queue from its first box, adopting or merging rewrites the box's WODs
and tells the owner, one queue together with the public page's «Πρότεινέ
το» disciplines, 2A («+ Κι άλλος τύπος») and 2C (a type per section in
sectioned WODs), no cap, a WOD counts once in each family it has, filters
match any type. ANR then asked for **no main type** («it is confusing»).

## Decision

### Type references
A WOD's types are a set of references (`master_workouts.types text[]`):

- a Palee kind key: a built-in `WorkoutType` key (`crossfit`) or a kind the
  Palee team added (`workout_kind_additions.key`, same slug alphabet);
- a box type: `box:<uuid>` (`organization_workout_kinds.id`).

`Workouts.Domain.WorkoutKinds` owns the grammar, the order (built-ins in
catalogue order, then additions by family and key, then box types by
folded label: stored order is never meaningful), validation against the
box's catalogue (a hidden box type stays valid on a WOD that already has
it, as ADR-275 keeps a hidden kind) and the families. The set is never
empty on a published WOD; there is **no cap** and **no main type**.

`master_workouts.families text[]` holds the families of the types, written
with them, so stats, colours and filters never look a box type up.
`master_workouts.type` stays as a derived compatibility column (the first
built-in kind of the set, else null) for readers that have not moved yet;
nothing user-facing reads it as "the" type.

Sections: `workout_sections.types text[]`. In a sectioned WOD where any
section has types (2C), the WOD's types are the union of its sections'
types; otherwise the WOD's own field decides (2A).

Writes accept `types` and, for old clients, `type` (read as `[type]`).

### Box types
`organization_workout_kinds` (tenant table, RLS): `label` as typed (shown in
every language, like class type names), `folded` (lowercase, no accents or
tonos, final sigma, single spaces; unique per box), `family` (required, one
of the nine), `status` `active | hidden | merged`, `merged_into` (a
reference) and `created_by_id`. Any staff member who can author WODs
creates one from the picker; owners and admins rename it, change its family,
hide it or merge it into another type (Palee or the box's) in Settings.
A merge rewrites the box's WODs and sections in one transaction. The merged
type keeps its row (`status = merged`, `merged_into`), so a training log
entry keeps the types it had on the day of training and still reads, through
`merged_into`, as the type it became; logs are never rewritten.

«Μήπως εννοείς…» runs in the client, which holds every translated label:
the same folded fuzzy match the exercise suggestions use, over the Palee
kinds in the reader's language plus English, the additions and the box's
types.

### The Palee team's queue
`workout_kind_candidates` (platform table, no person): one row per folded
name across boxes, with the first label, the families boxes chose (counts),
the boxes (`organization_ids`) and how many of their WODs use it, plus the
public page's discipline suggestions with the same folded name (`profile
suggestions` count). It enters the queue from its **first** box. The
vendor console («Προτάσεις τύπων», `/platform/workout-kinds`) lists both
sources in one queue and decides:

- **Νέος για όλους**: adds `workout_kind_additions` (key, family, a label
  for every locale; the console pre-fills them from the label) and rewrites
  every matching box type to that key;
- **Ίδιο με…**: rewrites every matching box type to an existing kind;
- **Μένει στο box**: the box types stay; the row leaves the queue.

A rewrite marks the box type `merged` (`merged_into` = the key), runs per
box in that box's tenant context (`ApplyWorkoutKindDecisionJob`) and sends
the owner the `workout_kind_adopted` notification. Matching discipline
suggestions are resolved (`added` / `declined`). Every decision is stored on
the candidate (who, when, what), the audit trail.

A daily job (`WorkoutKindDigestJob`) emails the Palee team (`config
:palee, :palee_team_emails`) the candidates and discipline suggestions that
arrived since the last digest; it sends nothing on a day without news.

### Readers
- **Stats and badges** count a completed WOD once in each family it has
  (`AchievementRules.milestone_badges/2` takes family counts).
- **Challenges**: «X WOD of type Y» and the `workout_type` rule match when Y
  is one of the WOD's types; `rare_workout_type` looks at the rarest of
  them.
- **Filters** (library, Vault) match a WOD that has any of the chosen
  types; a family filter matches any type of that family.
- **Colour and icon**: one family gives its colour and icon; several
  families split the stripe into their colours in catalogue order and use
  the «μικτή προπόνηση» icon.
- Timers, goals, formats and rank ladders do not read the type and do not
  change.

## Rationale
- The family keeps every stat comparable from day one, so a box never waits
  for Palee; the Palee list stays the shared vocabulary and box lists stay
  small because adopted names fold back into it.
- References instead of labels let a rename, a merge or an adoption change
  one row and a few arrays, never free text.
- Additions live in the database, so the Palee team adds a kind for
  everyone without a deploy.

## Alternatives Considered
- 1B (no family until Palee decides) and 1C (suggestion only): not chosen.
- 2B (checkbox list): every author would see checkboxes for one type.
- A main type (★): ANR found it confusing.
- Replacing `type` with `types` everywhere at once: kept as a derived
  column so old clients and slow readers keep working.

## Consequences
- An adopted kind's labels come from the database (served with the authoring
  settings), not from the message catalogues.
- `Ui.semanticWorkout*` keys stay for the built-in kinds.
