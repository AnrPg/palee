# ADR-392: Booking email with the calendar invite
Date: 2026-11-03
Status: Accepted

## Context
ADR-359 gave every booking an `.ics` invite (`GET /api/org/:slug/bookings/:id/calendar.ics`, the
same UID as the personal feed, `METHOD:CANCEL` once cancelled) and noted under «Alternatives»:
«Booking emails with `.ics` attachments: Palee sends no booking emails (push only)». The product
owner (ANR, v3.1 questions of 2026-11-03, item 10) asked for the email anyway: one email when a member
books a class, and when the booking or the class is cancelled or the class moves, with the invite
attached, and a switch to turn it off. This ADR supersedes that line of ADR-359. ADR-199 had kept
`email` as a known channel no category offered.

## Decision
### When
`Scheduling.Domain.BookingInviteEmail.decide/2` (pure):
- **Booked** – a seat is confirmed: booked with automatic confirmation (`:booking_made`), approved by
  staff or promoted from the waiting list (new event `:booking_confirmed`), and its class is live. A
  request waiting for staff or a waiting-list place is not a seat yet and gets nothing.
- **Changed** – the class of a confirmed seat gets another start, length or branch (new event
  `:class_moved`, published by `UpdateScheduledSlot` for every class an edit reached; capacity, coach,
  WOD or name edits do not count, `BookingInviteEmail.moved?/2`).
- **Cancelled** – the seat is withdrawn by the person or by staff, or its class is cancelled
  (`:booking_cancelled`, which now carries `previous_status` and `guest_name`): sent when the seat had
  been confirmed or already had an invite. A request that was never confirmed is withdrawn silently.
  A withdrawn booking row is deleted, so the handler rebuilds the cancelled seat from the event and its
  class, which still exists.
- Guest-pass seats (a guest's name on the booking) get nothing: the guest has no address here.

### What
- One outbox email (ADR-203), kind `:booking_invite` (`Palee.Email.Templates.BookingInvite`),
  category `transactional`, origin `:box` (ADR-368): the demo gate (ADR-184), suppression, one-click
  unsubscribe of the kind (ADR-212), throttle (20 a day per address) and budget all apply.
- Subject and body in the person's language (12 locales, `emails` gettext domain): «Κράτηση: CrossFit,
  Τρίτη 24/11 19:00» / «Άλλαξε το τμήμα: …» / «Ακυρώθηκε: …», the class, when (weekday translated, day
  and time on the gym's clock, ADR-176/179) and where, a link to the class in the app, and «Μπορείς να
  σταματήσεις αυτά τα email στις Ρυθμίσεις › Ειδοποιήσεις».
- Attachment `text/calendar; method=REQUEST|CANCEL; charset=UTF-8` (the outbox now accepts
  `text/calendar` besides PDF): `BookingCalendarInvite.build/5` with `invite: true` renders the same
  event as the download and the feed (UID `class-<class id>@palee`, STATUS, LOCATION) with
  `METHOD:REQUEST` (RFC 5546), the box as `ORGANIZER` (its name, the sender address) and the person as
  `ATTENDEE` (`PARTSTAT=ACCEPTED;RSVP=FALSE`: the booking is the answer). A cancelled seat or class is
  `METHOD:CANCEL`, `STATUS:CANCELLED`.
- SEQUENCE: the ADR-359 rule (seconds since 2026-01-01 of the latest change of class and seat), kept
  above every invite of the booking already emailed (`BookingInviteEmail.sequence/2`), so a change in
  the same second still reads as newer.
- Idempotency key `booking_invite:<booking id>:<kind>:<derived sequence>:<sent sequence>`: a repeated
  event for the same state sends nothing (`already_sent?/4`), a real change always sends.
- Sent regardless of a calendar subscription: the UID matches, so calendars merge the two.

### The switch
- `NotificationCategories`: the `bookings` category offers `email` (ADR-199's channel) besides
  `in_app` and `push`. On by default (no stored row), independent of the bell. Changed with the
  existing `PUT /api/notifications/preferences/bookings {email: false}`; `GET` reports it. No
  migration: the table already allowed the channel.
- `Notifications.channel_enabled?/3` (query `DeliversNotification.category/3`) is checked by the
  handler before anything is rendered.
- Web: under «Κρατήσεις & τμήματα» in Ρυθμίσεις › Ειδοποιήσεις, one switch «Email κράτησης με
  ημερολόγιο» with its hint (12 locales); the columns stay «Στην εφαρμογή» and «Push».

### Where
`Palee.Application.BookingInviteEmails`, a domain event handler (ADR-144) for `:booking_made`,
`:booking_confirmed`, `:class_moved` and `:booking_cancelled`. It runs after the booking's write and
never fails or blocks it; an outbox refusal is logged at info level.

## Rationale
- Events already announce every seat change; one handler keeps the booking code unaware of email.
- Reusing the invite builder guarantees the email's event is the feed's event.
- A category channel follows ADR-199's plan for email («added to a category's `channels`, the check
  runs in that email sender, and the UI adds a column»), except that one switch is enough: only
  bookings has email.

## Alternatives Considered
- A timer to collect several changes into one email: a move is one save, and a cancellation should
  arrive at once.
- Emailing pending requests as `TENTATIVE`: a request may be rejected; the push already tells the
  person, and the email comes when the seat is theirs.
- Not sending to people who subscribed to the feed: ANR asked to send regardless; the UID merges.

## Consequences
- More transactional mail per active member (one per booking, plus moves and cancellations), within
  the per-address throttle and the daily budget (deferred, never dropped, ADR-203).
- A demo business sends no booking emails (ADR-184), like every transactional email.
- Seats confirmed before this change get no first email; a later move or cancellation of a confirmed
  seat does send.
- Classes deleted with `delete_slots_for_workout` (no bookings can remain on a deleted class
  otherwise) send nothing.
- No new person data: the email log is ADR-203's platform table; the switch is a
  `notification_preferences` row, already in the data download (ADR-267).

## Implementation Notes
- Events: `:booking_confirmed` (ResolveBooking approve, PromoteClassWaitlist) and `:class_moved`
  (UpdateScheduledSlot) are new; `:booking_cancelled` gained `previous_status` and `guest_name`.
- Tests: `test/palee/scheduling/domain/booking_invite_email_test.exs` (decision, keys, SEQUENCE,
  ORGANIZER/ATTENDEE), `test/palee/email/templates/booking_invite_test.exs` (every locale),
  `test/palee_web/controllers/booking_invite_email_test.exs` (API under RLS: book, approve, withdraw,
  move, box cancel, the switch, Greek), notification categories, web vitest
  `notification-preferences.test.ts`.
