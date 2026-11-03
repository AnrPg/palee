# ADR-359: Visit badges, calendar invites with updates and cancellations, staff notes
Date: 2026-10-31
Status: Accepted

## Context
- CP-E1: staff should see «first visit» and «Επισκέπτης» (the box role `guest`, ADR-272) on class
  lists and at check-in, and how the person came (event, member).
- CP-E4: Palee already had a personal `.ics` feed with a signed, rotatable URL
  (`/api/calendar/feed.ics`, `CalendarFeedToken`), but a member's cancelled seat simply vanished from
  the feed (calendars kept the stale event), there was no SEQUENCE, no location and no invite for one
  booking.
- CP-E5 (check): private coach notes (ADR-101) are read by the author, owners and consenting admins;
  the front desk could neither read nor write any note about a member.

## Decision
### Visit badges (CP-E1)
`Scheduling.Domain.VisitBadges`: `first_visit`, `first_in_class_type`, `guest` (only the guest role),
`trial`, `brought_by_member` (guest pass), `came_via_event` / `came_via_referral` (latest referral
attribution, first visit only). Visits = approved classes that already took place and were not marked
missed, plus check-ins, before the class (never the class itself). Port `VisitFactsStore` (Ecto
adapter). `GET /admin/schedule/slots/:id/visit-badges` (capabilities `run_classes`, `check_in`,
`manage_schedule`; branch scope applies); the desk check-in response gains `visit: {badges, via}`.

### Calendar (CP-E4)
`Scheduling.Domain.ICalendar` renders RFC 5545 with line folding. A seat keeps the class's UID
(`class-<id>@palee`) for good; `STATUS` follows the seat (`CONFIRMED`, `TENTATIVE` for pending or
waitlisted, `CANCELLED` for cancelled/rejected seats or cancelled classes); `SEQUENCE` = seconds from
2026-01-01 to the latest change of the class or seat (monotonic, no counter to store);
`LAST-MODIFIED`; `LOCATION` from the branch. The member feed keeps cancelled seats in its window as
`CANCELLED`. `GET /api/org/:slug/bookings/:id/calendar.ics` gives one booking as an invite with the
same UID (`METHOD:CANCEL` once cancelled). The private feed URL and its rotation are unchanged.

### Staff notes (CP-E5)
`coaching_notes.audience` (`private` default | `staff`, migration `20270505000200`). A staff note is
read by owner, admin, coach and front desk (the roles that see the directory; never the janitor,
and never the accountant: ANR confirmed 2026-11-03),
written by anyone with `view_directory` for members they may see, edited only by its author, and its
reads are not logged (it is shared on purpose). Private notes keep ADR-101 exactly.

## Rationale
Badges are derived on read from existing records (nothing to keep in sync). Deriving SEQUENCE from
timestamps keeps the feed stateless. A separate audience keeps ADR-101's privacy for coach notes
while giving the desk Kilo's «internal comments».

## Alternatives Considered
- Booking emails with `.ics` attachments: Palee sends no booking emails (push only); the invite
  endpoint covers «add to calendar». Email delivery is an open question.
- Opening private coach notes to the front desk: rejected, they hold sensitive context (ADR-101).
- A VTIMEZONE block: single events are in UTC; only staff recurring events use TZID (as before).

## Consequences
- «Member of another box» is not shown: it would leak memberships across tenants. Open question.
- Notes are not in the member's data download (they are about, not by, the member), as before.
- Screens wait for the product owner's mockup pick.
