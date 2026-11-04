# ADR-463: Staff say once whether they also train with Palee
Date: 2026-11-04
Status: Accepted

## Context
Every new account goes through the same first run (ADR-183): photo, «Τι
κάνεις;» (sports) and «Πού προπονείσαι;» (area and the box question). A coach,
front desk employee or accountant who joined through a staff invitation and
does not train has to skip the last two, and later still sees prompts meant
for athletes. The product owner picked option Γ of the onboarding mockup
(2026-11-04, `mockups-2026-11-04.html`, tab 1): one question first.

## Decision
- **One question for staff.** Anyone holding a staff role in any business
  (owner, admin, coach, front desk, accountant, cleaning staff; from
  `/memberships`, so a staff invitation counts) gets, right after the photo,
  «Θα προπονείσαι κι εσύ με το Palee;» with the role and the business in the
  lead («Μπήκες ως Coach στο <box>.»), two option cards («Ναι, προπονούμαι κι
  εγώ» / «Όχι, μόνο για τη δουλειά»), «Συνέχεια» and the note «Αλλάζει όποτε
  θες στο Εγώ › Ρυθμίσεις.». «Ναι» goes on to sports and area as before;
  «Όχι» finishes the first run. Members and athletes see the first run
  exactly as before.
- **Stored on the profile.** `users.trains_with_palee` (boolean, NULL = never
  asked). NULL and `true` both mean "trains", so members, athletes and
  everyone created before this change keep every prompt.
  `PUT /api/me/trains-with-palee` `{trains_with_palee: bool}` →
  `{trains_with_palee: bool}` (`Application.SetTrainsWithPalee` →
  `Identity.update_trains_with_palee/2`); `/auth/me` (and the login and
  refresh user) carry `trains_with_palee`. Deleting a kept profile clears it.
  It is a `users` column, so «Λήψη των δεδομένων μου» (ADR-267) exports it
  with the rest of the profile.
- **Εγώ › Ρυθμίσεις › «Προπονούμαι κι εγώ με το Palee»**: a switch for anyone
  with a staff role, and for anyone whose answer is `false` (so it can always
  be undone). Members never see it.
- **What `false` hides** (web `lib/athlete-use.ts` `usesAppAsAthlete(user)`,
  the one helper every gate calls): the sports and area steps of the first
  run, the weekly goal and rest days section in Ρυθμίσεις («Πρόγραμμα
  προπόνησης»), and the «Τα αθλήματά μου» chip of Γύρω μου. Staff tools,
  the console and everything the person opens on purpose stay as they are.

## Rationale
One question asked once costs staff one tap and saves the two steps and the
prompts afterwards; a separate "I don't train" button on the sports step
(option Β) was easier to miss. NULL as "not asked" keeps the default for
everyone else without a backfill.

## Alternatives Considered
- Α, unchanged: staff skip twice and keep seeing athlete prompts.
- Β, a third button on the sports step: works, but the question comes after
  a screen that already assumes the person trains.
- Inferring it from the roles (no client role = not training): a coach often
  trains at their own box without a member role, so it must be asked.

## Consequences
- Prompts added later that are aimed only at athletes should call
  `usesAppAsAthlete` instead of adding their own rule.
- Box › «Βρες box» stays: it only shows without any membership, which a staff
  member never is.

## Implementation Notes
- Migration `20270713000000_add_trains_with_palee_to_users`.
- The answer is saved before the step moves on; a failed save keeps the
  person on the step with «Δεν αποθηκεύτηκε».
