# ADR-746: A class can hold several WODs, with one «Τώρα» everybody follows
Date: 2026-11-23
Status: Accepted (amends ADR-138 D6 «#wod-σήμερα», ADR-176 box screens, ADR-230 day WODs)

## Context
The product owner asked (2026-11-22): "can a class have more wod? this should be allowed (and coach/members choose live or swap back and forth)". Two sets of clickable mockups were discussed. The picks were 1A–8A for the class and the screens, and 1A–4A for booking (2026-11-23). Every small question was answered "yes".

## Decision
- **Data.** The first WOD stays in `scheduled_classes.master_workout_id`, so nothing that reads it changes. The extra WODs go in the new table `scheduled_class_workouts` (organization_id, scheduled_class_id, master_workout_id, position; RLS by tenant; unique per class and WOD). `scheduled_classes.live_workout_id` holds «Τώρα». When it is null, «Τώρα» is the first WOD. `bookings.chosen_workout_id` holds the member's choice. When it is null, the member decides at the box.
- **Domain.** `Scheduling.Domain.ClassWorkouts` is pure. It gives the ordered ids, `live_id`, `chosen_id`, `effective_id`, list validation (one to N, no duplicates, archived WODs refused) and `after_change`. When a WOD is removed, the live WOD and the choices that pointed at it move back to the first WOD or are cleared. It also gives the choice counts per WOD. Seats are shared across the WODs of a class.
- **Commands.** These are `SetClassWorkouts` (staff), `SetClassLiveWorkout` (staff) and `ChooseClassWorkout` (the member, for their own booking, or staff for anyone's booking, even after the member chose). They go through the port `SchedulingStore` and its Ecto adapter, which runs them in one transaction.
- **Class timer per WOD.** Each WOD of a class has its own timer row. `ClassTimerView.load/3` takes an optional WOD. Without one, it gives «Τώρα» with `workouts`, `live_workout_id`, `live` and `other_timers`. When the coach moves «Τώρα» while a clock runs, they are asked to stay, to switch and pause (the default, which keeps the progress), or to switch and keep it running. A timer still running behind shows in a bar with «Πίσω σε αυτό». A member can follow the coach or «Κάνω άλλο WOD» (`?workout=`). Pushed payloads are filtered by `followsPayload`.
- **Box screens.** `box_screens` gains:
  - `space_id`, the «Χώρος» of the screen (it must be the same branch and not archived). In automatic mode the screen shows the class of its space first. With no class there, it falls back to the whole branch.
  - `concurrent_mode`, either `room` (the default) or `split` («Μοιρασμένη οθόνη»). It shows two classes that run together side by side.
  - `override_workout_id` and `override_split_slot_id` on the staff pin. A pin can choose which WOD a screen shows.
  Any coach with a class that day can take a screen. A confirm appears only when it shows a running timer of another class. The coach who loses the screen gets the new notification `box_screen_taken` (bell and push, staff category), with the way back from their class timer. The TV shows one leaderboard per WOD.
- **Member.** The schedule row and the class sheet show the WODs as pills that open the chosen WOD in full. The seats line «3 / 6 ελεύθερες ▾» opens counts per WOD. The choice chips are «Ποιο WOD; · προαιρετικό», with «Θα αποφασίσω στο box» first and as the default. When WODs are locked, the member sees only «N WOD» (ICU plural). In `#wod-σήμερα` (`GET /community/wod-today`), the first WOD stays the card, and each other WOD of the day is in `more` with its own classes and leaderboard.
- **«Ξεχωριστό WOD για άτομα».** Staff search all box members. Results come in two sections, «Έκλεισαν θέση» then «Άλλα μέλη», and update as staff type. A member who has not booked is not booked by it. `ProgramUserWorkout` with `offer_booking: true` puts the WOD in their programme for that day. The existing `workout_assigned` notification then carries `class_slot_id` and a link to that class in the schedule, with «Κράτηση».
- **Errors** (FallbackController, 422): `not_a_class_workout`, `invalid_class_workouts`, `invalid_screen_space`, `invalid_screen_settings`.

## Consequences
- Migration `20271123104500_class_multiple_workouts` is reversible. Down keeps the first WOD and deletes the `box_screen_taken` notifications.
- `scheduled_class_workouts` is declared in `Tenancy.Audit` and in the Scheduling `TenantDataPolicy`. It is class data, not personal data. `bookings.chosen_workout_id` is exported with the person's bookings.
- New UI words («Τώρα», «Θα αποφασίσω στο box», «Μοιρασμένη οθόνη», «Χώρος» of a screen) are in `docs/product/ontology.md`.
