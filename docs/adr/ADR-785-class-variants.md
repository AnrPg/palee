# ADR-785: A member's «Παραλλαγή» of one class
Date: 2026-11-28
Status: Accepted

## Context
ANR's TODO (2026-11-28): staff can give someone a variation of the WOD before the class has
even closed, for one specific day and class. A class variant already existed (ADR-125: an
assigned workout linked to the class occurrence with `source_scheduled_class_id`), but it
was reached only from the member's profile, needed the package's online programming
(ADR-225) and was called «εκδοχή»/«version» in places. ANR added that it needs no online
programming and can be given even while the class runs: the member keeps what they did and
then does the new WOD. Mockups with alternatives and «Οι επιλογές σου» were discussed
(thread «Παραλλαγή WOD για ένα τμήμα»); ANR picked 1A, 2A, 3A, 4A, 5A, 6A and α–ζ «ναι».

## Decision
- **1A, entry points**: the roster row menu «Παραλλαγή μόνο για …» (and «Αλλαγή
  παραλλαγής…» / «Σβήσιμο παραλλαγής» once there is one, **ε**); the class ⋯ «Παραλλαγή για
  άτομα» for several people; the member's profile, where the day lists the classes they
  booked first and then the other open classes of that day.
- **2A, who**: anyone who may do the class. No online programming is needed
  (`AssignWorkout.programming_grants/3` skips `AuthorizeProgramming` when a class is given;
  doing it needs `execute_class_workouts`, like the class). Nothing is charged. Making one
  needs `manage_coaching`, as the other variation routes.
- **3A, where it starts**: from the WOD the member does in that class (their pick, else
  «Τώρα», else the first; `ClassWorkouts.effective_id`), with the class's other WODs, the
  library and a new WOD offered; the editor can open first. An optional «Γιατί» goes in
  `instructions` and the member sees it.
- **4A, the member**: «Η παραλλαγή σου · από coach X» with the «Γιατί». They can go back to
  a WOD of the class (`PUT /schedule/slots/:id/my-variant {active:false}` sets
  `variant_set_aside_at`; the variant stays) and back to it.
- **5A, the class WOD changes**: the variant stores the WOD it stands in for
  (`variant_of_workout_id`, `ClassVariant.stands_in_for/3`) and that WOD's content hash
  (`variant_source_hash`, ADR-357). The roster says «Το … άλλαξε μετά την παραλλαγή» (or that
  the WOD left the class) with «Κράτησέ τη» (`POST /admin/schedule/slots/:id/variants/:assignment_id/keep`
  takes today's hash) and «Φτιάξ' τη ξανά».
- **6A, leaderboard**: the variant's best result appears in the day leaderboard of the WOD it
  stands in for, after Rx and Scaled, unranked (`rank: null`, `variant: true`), tagged
  «Παραλλαγή». The share card gives it no place.
- **α**: from now until the class ends (start + duration), also while it runs; a cancelled
  or ended class refuses with `class_variant_closed` (422).
- **β**: it never books. A member who has not booked gets the notice with «Κράτηση»
  (`offer_booking`).
- **γ**: a cancelled booking keeps the variant; a cancelled or deleted class removes its
  variants (`ClassVariants.handle_event(:class_cancelled, …)`).
- **δ**: bell only, no push (`silent: true`), opening the class.
- A new variant for the same person and class replaces the earlier one.
- **στ**: one name everywhere, «Παραλλαγή» / "Variation", in `docs/product/ontology.md`.
- **ζ**: the profile dialog always starts on «Παραλλαγή» and never switches by itself to
  «Αλλαγή για όλο το τμήμα».

## Consequences
- Migration `20271128173000_class_variant_details` adds four nullable columns to
  `assigned_workouts`; variants made before it are never reported as changed.
- Personal programming (a separate workout not tied to a class) still needs the package's
  online programming.
