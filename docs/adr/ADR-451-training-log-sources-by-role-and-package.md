# ADR-451: «Καταγραφή προπόνησης» sources follow role and package
Date: 2026-11-04
Status: Accepted

## Context
The journal's «Καταγραφή προπόνησης» sheet offered four chips to everyone:
Τμήμα, Προπόνηση που ανατέθηκε, Προπόνηση από τη βιβλιοθήκη, Ελεύθερη.
The product owner (2026-11-04): "The chip token choices in the journal must
correspond to the user's type and subscriptions … if he is not a box member
he doesn't see class … if he has no solo coach/personal trainer associated
why see the assigned wod? … Free wod is always available."

Before this ADR the API only filtered the library by role
(`[:owner, :admin, :coach, :member]`), so a member whose package had no
library could still log library WODs, while starting the same WOD as an
execution needed the `workout_library` channel (ADR-098).

## Decision
- **Pure policy** `Execution.Domain.TrainingLogSourcePolicy` decides from
  facts; `Application.TrainingLogSourceAccess` gathers them (club kind,
  role, package) with one entitlement read and one ledger check.
- **Τμήμα (`class`)**: a `member` whose package covers
  `in_person`/`book_classes` under the club's rollout mode
  (`Finance.check_entitlements/3`, the booking check); an `athlete` only with
  an explicit grant; anyone with an approved booking of the last 30 days
  still to log (guests, staff who trained, a package that just ended). The
  package path is closed in a solo coach's club (`provider_kind: "coach"`).
- **Προπόνηση που ανατέθηκε (`assigned_workout`)**: `ProgrammingGrant.of/1`
  (online programming or personal training, strict, ADR-225), or an
  assignment of the last 30 days still to log. Assigning already needs the
  grant, so a leftover assignment means the grant held when it was made.
- **Βιβλιοθήκη (`library_workout`)**: the self-selected-execution rule.
  Owner, admin and coach by role; `member` by package
  (`workout_library`/`execute_library_workouts`, rollout mode); `athlete`
  only by explicit grant (ADR-029: athletes follow what they are assigned);
  other roles never. The club must have at least one published WOD.
- **Ελεύθερη (`freeform`)**: always.
- `GET /me/training-log/sources` returns `available_sources` (display
  order, freeform last); a list is empty when its type is not available.
- `AuthorizeTrainingLogSource` enforces the library rule on create and now
  refuses a draft (unpublished) WOD with `not_found`. Class and assignment
  logs already require the person's own booking or assignment.
- Web: the picker shows only `available_sources`, no chips before the
  answer arrives, and no chip row when only «Ελεύθερη» is left.

## Consequences
- A box in `observe` rollout mode keeps today's behaviour for members
  (classes and library visible); an enforced box hides what the package
  lacks.
- Logging and starting a library WOD now agree on who may do it.
- Offline replays of an accepted entry are unaffected (ADR-120): a replay is
  matched before the source is authorized again.
