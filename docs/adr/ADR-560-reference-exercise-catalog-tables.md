# ADR-560: The exercise catalog and what each exercise trains are database tables
Date: 2026-11-09
Status: Accepted

## Context
ADR-163 kept the muscle taxonomy, the ten fitness qualities and the map from each
Quick Text catalog exercise to the muscles it trains (primary, secondary, stabilizer)
and the qualities it develops in code (`MuscleTaxonomy`, `FitnessQualities`,
`ExerciseTargets`), next to the catalog itself (`ExerciseCatalog`). WOD goals are
suggested from that map and the coach edits them before members see them.

The owner asked (2026-11-09) for the catalog and the map to be database tables. In
code, a new exercise or a corrected role needs a release; an exercise the Palee team
approved from typed names (ADR-461) reached suggestions but never Quick Text, the
WOD-goal suggestion, coverage or the injury policy, because those read only the code.

## Decision
1. **Reference tables** (migration `20271109150000`): `muscles` (region → group → head,
   own atlas TA2 mesh ids, position), `fitness_qualities`, `exercises` (slug id, label,
   normalised label unique, category, origin `builtin|reviewed`, position),
   `exercise_aliases` (`resolve` = Quick Text resolves it, unique across the catalog;
   `search` = suggestions only), `exercise_muscle_targets` (one role per muscle per
   exercise; composite FK `(muscle_id, muscle_kind)` → `muscles(id, kind)` with
   `muscle_kind IN ('group','head')`, so a region can never be a target, no trigger),
   `exercise_quality_targets`, and the singleton `reference_catalog_state`
   (`revision`, `taxonomy_version`). Platform data holding no person: no RLS.
2. **Seed = the code as it was.** `priv/repo/reference/exercise_catalog_seed_2027_11_09.json`
   was exported from the modules; the migration loads it and carries over the approved
   additions (entry → `reviewed` exercise, alias → `resolve` alias). A test asserts
   the tables equal the seed for built-in rows.
3. **One indexed in-memory copy per pod.** `Palee.Catalog` builds a
   `Catalog.Domain.Reference` (tree order, children, node order, resolve index, sorted
   targets) from one SQL statement (`Infrastructure.Catalog.EctoReferenceStore`, one
   consistent snapshot, one round trip) and keeps it in `:persistent_term`.
   `Catalog.Cache` loads it at boot and polls `revision` every 30 s; a statement
   trigger on each table bumps the revision, so every pod reloads after any write,
   with or without clustering. The writing pod reloads at once (`Catalog.refresh/0`).
   If the database cannot be read and nothing is loaded yet, the copy comes from the
   seed file (logged as an error) until the next successful poll.
4. **The domain modules keep their API.** `MuscleTaxonomy`, `FitnessQualities`,
   `ExerciseCatalog` and `ExerciseTargets` now read the copy; compile-time module
   attributes derived from them became runtime lookups. Category capabilities stay in
   code (they are Quick Text behaviour, not data).
5. **Writes through the vendor console, audited.** Approving a candidate as an entry
   may carry `muscles: [{id, role}]` and `qualities`, validated like WOD goals; the
   exercise, its targets, the addition and the audit event are written in one
   transaction. `GET /api/platform/exercise-catalog` lists every exercise with aliases
   and targets; `PUT /api/platform/exercise-catalog/:id/targets` replaces them with a
   `set_targets` audit event holding before and after.
6. **WOD goals are unchanged in behaviour.** The coach's «Στόχοι» panel already
   pre-fills muscles by role and qualities from the workout's exercises and follows the
   suggestion until the coach edits it (ADR-163 D3); it now reads the tables, so an
   approved exercise with targets feeds it the moment it is saved.

## Rationale
- Tables let the Palee team grow and correct the map without a release, with an audit
  trail, and give every consumer (Quick Text, suggestions, WOD goals, coverage, atlas,
  injury policy, AI prompts) the same, single vocabulary.
- An in-memory copy keeps the per-call cost of the old module attributes (lookups are
  map reads with no copy) while the database stays the source of truth; polling a
  one-row revision is cheap and works without Erlang clustering.
- The composite FK and check constraints make invalid targets impossible at the
  database, not only in the use case.

## Alternatives Considered
- **Query the tables on every call**: hundreds of lookups per workout parse or
  coverage build; rejected.
- **LISTEN/NOTIFY or PubSub only**: lost notifications leave a pod stale forever; the
  revision poll is the guarantee (PubSub could be added for speed).
- **Keep the taxonomy in code and only move exercises**: targets could then not have a
  foreign key to the muscles they name.
- **Store targets as jsonb on `exercises`**: no foreign keys, no per-muscle index for
  «which exercises train this muscle».

## Consequences
- Changing the taxonomy (adding or removing a node) is a migration that also bumps
  `reference_catalog_state.taxonomy_version`; the atlas asset and client translations
  (`anatomy.muscle.<id>`) must ship with it.
- The injury-risk policy (ADR-124) and exercise equipment (ADR-542) are still keyed by
  catalog id in code; a reviewed exercise has no injury or equipment rule until one is
  added there.
- A reviewed exercise approved without targets is `nil` for `ExerciseTargets.fetch/1`
  (counted as «not recognised» by the goal suggestion) until the team sets them.
- The vendor console UI for editing targets needs mockups first (owner rule); the API
  is ready.
- Tests that write catalog tables must be `async: false` and restore the copy on exit
  (`Catalog.put/1`).

## Implementation Notes
- `GetAnatomyTaxonomy` computes its ETag per call from the copy (was a compile-time
  constant).
- `ExerciseNames.catalog_documents/0` and the Quick Text manual no longer merge the
  additions table; it stays as the decision record.
- Tests set `:reference_catalog_poll_ms` to `nil`; production polls every 30 s.
