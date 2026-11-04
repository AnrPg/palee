# ADR-540: A bought programme is a sequence of days: «Έμεινε πίσω», «Κάν' τη σήμερα», «Παράλειψη»
Date: 2026-11-04
Status: Accepted (amends ADR-371's delivery)

## Context
Until now a purchase followed the calendar from `starts_on` (ADR-371): day `n`
of the version fell on `starts_on + n`, and a day the buyer did not train
simply passed. The programmes UX board (2026-11-04, screens 3κ/3μ «Η μέρα
μου», question 1) proposed a card «Έμεινε πίσω η Ημ. 2» with «Κάν' τη σήμερα»
and «Παράλειψη», so no session is lost unless the buyer chooses it. ANR
approved it.

## Decision
1. **Days, not a calendar.** `PurchaseSchedule` (pure) lists every day of the
   version (`0..weeks×7-1`) with its date and a status: a day without WODs is
   `rest`; a training day is `done` (every WOD the purchase assigned for it was
   finished: an in-app run of that assigned workout or a training-log entry of
   it), `skipped`, `behind` (date before the seller's today), `today` or
   `upcoming`. Progress counts training days (`total`, `done`, `skipped`,
   `behind`, `remaining`); the card names the earliest behind day.
2. **Storage on the purchase.** `programme_purchases.day_dates` (jsonb
   `"n" => "YYYY-MM-DD"`, only the days whose date changed) and `skipped_days`
   (int[]). No new table: the rows stay the seller's (tenant RLS, FORCE) and
   the buyer reaches them only through their own purchase (`user_id`), like
   every buyer route of ADR-371.
3. **«Κάν' τη σήμερα»** on a behind day moves it to today and every later
   training day that is neither done nor skipped by the same number of days,
   so the coach's order and gaps stay; done and skipped days keep their dates;
   a rest day moves with the training day before it. `ends_on` follows the last
   day. Only a behind day can be moved.
4. **The cap.** A programme never ends more than its own length after its
   planned end: `latest_end = planned_ends_on + weeks × 7` (a 6-week programme
   takes at most 12 weeks). A move past it is refused
   (`programme_schedule_limit`, 409); the payload says so beforehand
   (`behind.can_do_today`), and skipping is always possible.
5. **«Παράλειψη»** marks a behind day skipped; nothing moves and its WODs stay
   in the past of the buyer's calendar.
6. **Refunds keep the planned period.** `planned_ends_on` keeps the end the
   purchase was sold with; withdrawal and `pro_rata` refunds (ADR-371) count on
   it, so catching up never changes money. Purchases made before this have no
   `planned_ends_on` until their first move (no backfill under forced RLS):
   their `ends_on` is the planned end.
7. **Assigned workouts move with their days.** In one transaction with the
   purchase row (locked `FOR UPDATE`): the buyer's own date on each assigned
   workout of a moved day (`assigned_workout_athletes.scheduled_for`, like
   «Μετακίνηση», so another buyer sharing the assignment keeps theirs) and the
   `programme_deliveries` rows. A moved day that was never assigned (a
   purchase paid after its start) is assigned on its new date. The buyer's
   apps get an `assigned_workouts` sync.
8. **API.** `GET /api/org/:slug/me/programme-purchases/:id/days`,
   `POST …/days/do-today` and `POST …/days/skip` with `{day}`, all answering
   `ProgrammePurchaseDays`. `GET …/programme-purchases/:id` shows moved dates.

## Consequences
- The Box › Σήμερα list keeps showing programme WODs as before; it now follows
  the moved dates.
- The sweep (ADR-371) completes a purchase after its (moved) `ends_on`.
- A day is `done` only when all its WODs are finished; a partly done day stays
  behind until the rest is done or the day is skipped.
