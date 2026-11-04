# ADR-461: Exercise names are free text with fuzzy suggestions, and the catalog grows through review
Date: 2026-11-04
Status: Accepted

## Context
The product owner (ANR, 2026-11-04): "In journal, notes, PRs and the WOD note
afterwards, wherever a user types an exercise, make it free text with
fuzzy-matching, Meilisearch-like dropdown autosuggestions." Mockup: tab 3 of
`stats-notifs-exercises/mockups-2026-11-04.html`, option A (one list with
groups). The value stays what the person typed; a picked suggestion also
links a catalog entry so analytics can count it. Suggestions forgive typos,
Greek and English ("σκουατ", "bak sqat"), accents and abbreviations (C&J,
T2B).

A follow-up from ANR the same day: "we already have something similar which
is used for WOD creation. if needed augment it or make it possible to be
augmented by a verified workflow." So the WOD editors' catalog
(`Workouts.Domain.WorkoutDsl.ExerciseCatalog`, served to the Quick Text and
structured editors as `vocabulary.exercise_catalog`) stays the one source of
Palee exercises; nothing parallel is built, and it grows only by the Palee
team's approval.

## Decision
- **Groups** (`GET /api/me/exercise-suggestions?q=&organization_id=&limit=`,
  any signed-in person): `{groups: [{source, items: [{name, catalog_slug,
  hint, uses_count}]}]}` in the order `mine` «Έχεις γράψει» (the person's own
  names: training log, PRs), `box` «Του box σου» (the exercise names of the
  box's published WODs; only when the person is an active member or staff of
  `organization_id`, otherwise silently left out), `palee` «Palee» (the
  catalog with its aliases). A name shows once, in the first group that has
  it (folded comparison). `hint` is the catalog category for a `palee` item;
  `uses_count` how often the person or the box used it. The web adds the
  last row «Κράτα «…» όπως το έγραψα».
- **One catalog.** `ExerciseCatalog` gains search-only aliases
  (`search_aliases/1`: Greek names and abbreviations such as T2B, CJ, OHP);
  `resolve/1` (Quick Text) does not match them, so DSL resolution stays
  unambiguous. Greek words also have English word synonyms
  (`ExerciseNames.word_synonyms/0`: σκουατ → squat, ντεντλιφτ → deadlift …),
  applied to the query and given to Meilisearch as synonyms.
- **Verified growth.** A remembered name that is no label or alias of the
  catalog becomes a candidate (`exercise_name_candidates`: counted uses and
  owners, deduplicated by folded form, holding no person). The vendor console
  (`/platform/exercise-candidates`, the `:vendor` pipeline, so platform staff
  only) approves a candidate as a new entry (label, category; the slug is
  derived and must be free) or as an alias of an existing entry, or rejects
  it. One transaction writes the addition (`exercise_catalog_additions`), the
  candidate's status and an append-only audit event
  (`exercise_catalog_audit_events`, `GET /api/platform/exercise-catalog-audit`).
  The effective catalog is the built-in one plus the approved additions:
  `Workouts.exercise_catalog_documents/0` for suggestions and
  `Workouts.dsl_manual_with_additions/0` for the WOD editors' vocabulary
  (NameCell, Quick Text suggestions). Only approved additions enter the
  «Palee» scope of the index; an approval refreshes it at once.
- **Own names show at once, unverified.** A person's and a box's own names
  are in their own groups as soon as the save's job ran, with or without
  review.
- **Port** `Application.Ports.ExerciseNameIndex` (`enqueue_record`, `record`,
  `search`, `rebuild`, `refresh_catalog`). Adapters:
  `Infrastructure.Search.MeilisearchExerciseNameIndex` (production; index
  `exercise_names`, docs `{id, name, normalized, aliases, scope:
  palee|org|user, organization_id, user_id, catalog_slug, category,
  uses_count}`, filterable `scope`, `organization_id`, `user_id`, typo
  tolerance from 3 letters (two typos from 7), ranking `uses_count:desc` last,
  one multi-search per request with one filter per group) and
  `PostgresExerciseNameIndex` (test, and the fallback whenever Meilisearch
  cannot answer).
- **Postgres is the source of truth** for remembered names
  (`exercise_names`, scope `user` or `org`, unique per owner and folded form,
  row-level security per owner). The fallback prefilters with
  `strpos` / pg_trgm `word_similarity(word, folded) >= 0.3` (explicit
  comparison, no `pg_trgm.*` setting, no function created: the production
  migration role is no superuser) and ranks in Elixir with the same rules as
  the web's `fuzzy` (`ExerciseNames.score/2`: every query word matches a word
  as a prefix, inside a word, or within one typo, two from seven letters).
  Folding (lowercase, accents and tonos stripped, final sigma) happens in
  Elixir before storing, so `unaccent` is not needed.
- **Sync.** Save paths queue `RecordExerciseNamesJob` (Oban, inserted in the
  save's transaction): `CreatePR` / `EditPR` / `UpdatePR`,
  `LogTrainingEntry` (created only) / `UpdateTrainingLogEntry`, and
  `PublishWorkout` (the box's names; drafts never count). New saves count one
  use; edits only add names. The job (`RememberExerciseNames`) links names to
  the catalog, upserts them, pushes them to Meilisearch best-effort and
  counts candidates. `ReindexSearch` rebuilds the index from the catalog and
  every member's and box's rows.
- **PRs keep the link**: `user_pr_records.exercise_ref` (nullable, ≤ 120),
  like `performed_exercises[].exercise_ref` and `workout_exercises.exercise_ref`.

## Rationale
- The catalog the coaches already use is the one people should land on, so
  analytics of members' logs and coaches' WODs count the same slugs.
- Approval keeps the shared catalog clean: a typo or a private note typed by
  one person never becomes a suggestion for everyone.
- Postgres as truth keeps counts exact and a dead Meilisearch harmless; the
  fallback is fast at per-person and per-box sizes.

## Alternatives Considered
- **A separate suggestions catalog** (the first draft of this change): rejected
  by ANR, it would split the Palee exercises in two.
- **Adding the Greek names to the DSL aliases**: Quick Text would then resolve
  "Σκουάτ" to one of several squats; kept search-only instead.
- **`exercise_catalog_entries` (Analytics)** as the persisted catalog: it is
  analytics' own vocabulary of movement patterns and is not what the WOD
  editors read; left as it is.
- **Flat list (mockup option B)**: hides where a suggestion comes from.

## Consequences
- The review queue shows by default only names at least two owners (people or
  boxes) typed (`min_owners`), so a name one person typed, which may be
  personal, is not shown to the Palee team unless they ask for it.
- Quick Text *resolution* (`ExerciseCatalog.resolve/1`, compile-time) does not
  yet know approved additions: they appear in the editors' suggestions and in
  the member inputs, and a picked addition stores its slug, but a Quick Text
  line naming one stays unresolved. Follow-up: pass the additions into DSL
  resolution.
- Candidates are counted from saves after this change; the migration backfills
  remembered names (PRs, training log, published WODs) but not candidates.
- Meilisearch needs one `Palee.Release.reindex_search/0` to hold the catalog;
  until then the «Palee» group is answered from memory.

## Implementation Notes
- Migration `20270711000000_create_exercise_names`.
- `exercise_names` is in the Workouts tenant data policy (its `org` rows) and
  in "Download my data" (its `user` rows).
- The platform tables have no row-level security, like the other vendor
  queues (`food_barcode_misses`); they hold no person besides the deciding
  vendor's id.
