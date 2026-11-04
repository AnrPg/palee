# ADR-542: Equipment on the exercise catalogue; «κύριος εξοπλισμός» and «περίπου ανά προπόνηση»
Date: 2026-11-04
Status: Accepted

## Context
The programme page of the board (2κ/2μ, question 2) shows «κύριος εξοπλισμός»
and «περίπου ανά προπόνηση». We had neither. ANR approved deriving them from
the WODs (equipment from the exercises, time from the WOD's duration), shown
only when known, with the author able to add or remove equipment.

## Decision
1. **Equipment on the canonical catalogue.** `Workouts.Domain.ExerciseEquipment`
   maps the Quick Text catalogue's ids (`WorkoutDsl.ExerciseCatalog`, the list
   the WOD editor and exercise suggestions use) to stable keys:
   `none barbell dumbbell kettlebell bench box pull_up_bar rings dip_bars
   climbing_rope ghd jump_rope wall_ball sled rower bike air_bike ski_erg pool
   band foam_roller`. It sits **beside** the catalogue, not inside its entries,
   so ADR-461's catalogue work (approved additions, search aliases) and this
   merge without touching each other. No invented defaults: an exercise done
   with different kit (goblet squat, lunge, farmer carry…) or not listed is
   unknown, never `none`; ADR-461 additions start unknown. The WOD editor's
   vocabulary (`GET /api/org/:slug/admin/workouts/dsl/manual`, `vocabulary`) carries
   `equipment_keys` and `exercise_equipment` (id ⇒ keys). Labels live in the
   web messages.
2. **A WOD's equipment** (`Workouts.workout_equipment/1`): the keys of its
   exercises, by catalogue ref or by name read leniently (ADR-163), `none` only
   when nothing else is needed.
3. **Programme facts** (`Programmes.Domain.ProgrammeFacts`, pure):
   `equipment` = keys by the number of sessions needing them, ties in
   vocabulary order, at most 5; `minutes_per_session` = the mean length of a
   training day (its WODs' `estimated_duration_seconds` added up), rounded to 5
   minutes, **null unless every WOD has a duration**. Timer-derived lengths are
   not used yet (TD-542).
4. **Frozen with the version.** Publishing stores the facts of the frozen WODs
   on the version (`programme_versions.facts`), so public reads never open a
   WOD; versions published earlier derive them on read. The editor derives them
   live from the draft (`facts` on the staff payload).
5. **The author's override: added and removed lists.** `programmes.equipment`
   now means the keys the author **added** (at most 10) and the new
   `equipment_removed` the derived keys they took away (vocabulary keys,
   `invalid_equipment` otherwise; older free-text values are ignored when
   read). Shown: added first, then the derived keys not removed
   (`main_equipment`). Lists, not a single override switch, so a later change
   of the WODs still shows for keys the author did not decide.
6. **Payloads.** Staff: `facts {equipment, minutes_per_session}`,
   `main_equipment`, `minutes_per_session`, `equipment`, `equipment_removed`.
   Public programme, box list, catalogue, box website: `main_equipment`,
   `minutes_per_session`.

## Consequences
- Meilisearch does not index exercises on `main` yet; ADR-461's exercise-name
  index does. Its catalogue documents should carry `equipment` (filterable)
  from `ExerciseEquipment` once both are merged (TD-542).
- The derived list is only as good as the map; unknown exercises simply do not
  contribute.
