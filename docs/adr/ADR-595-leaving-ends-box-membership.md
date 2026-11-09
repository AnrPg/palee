# ADR-595: Leaving ends the box membership at once

- Status: accepted (ANR, 2026-11-09)
- Supersedes parts of: ADR-220 (scheduled leave, «Μένω στο box», staff-chosen last day)
- Refines: ADR-274 (one status for member and staff)
- Mockups: `/mnt/project-files/milos/member-leave/member-leave-mockups-v2-2026-11-09.html`

## Context

Under ADR-220 «Αποχώρηση από το box» only scheduled a leave: renewal stopped
and the finance membership ended with the paid period, but nothing ever
closed `organization_memberships`, so the person stayed a box member for
good. The member also saw the subscription's lifecycle («ΕΝΕΡΓΟΣ») while staff
saw the derived «Ληξιπρόθεσμο», and months inside a minimum commitment were
no longer billed once the member had left.

ANR's model: the box membership and the money are separate. Leaving is free
and immediate; a package already bought stays usable to its last day, money
owed stays owed with reminders, following the box is untouched, and member
and staff always see the same status, with a grace stated plainly.

## Decision

Picks: 1A one dialog with «Τι μένει», 2A the box stays in Box marked «Δεν
είσαι μέλος», member channels and groups close at once, staff word
«Αποχώρησε» then «Πρώην μέλος box», 3A former members stay in the staff list
while anything is pending, 4A badge plus one line, commitment months stay
owed, no undo (join again from the box page), staff leave under the same
rules and the member is told.

Organizations:

- `organization_memberships` gains `left_at`, `left_by` (`member` | `staff`)
  and `access_until` (the last day of the kept package, nil when nothing was
  kept). The row stays `active` so the person still reaches the box for what
  they kept; "former member" means `left_at` is set.
- `current_memberships/1` (club scope, Γύρω μου, shop cards) leaves former
  members out, so the club, member channels and groups close at once.
  `provider_memberships` keeps a former member only while
  `today <= access_until` in the box's own time zone (`reaches_box?/2`).
- Joining again by any way in (join request, join link, invitation, the box
  page) goes through the `add_membership` upsert, which clears the leave.
  `:membership_activated` → `LeaveReactions` → `Finance.rejoin_after_leaving`
  resumes renewal of a package still running.
- Staff memberships never end through this flow.

Finance:

- Member and staff leaves both take the natural last day (paid period,
  commitment end, paid-through); the staff-chosen date and the
  commitment-override reason are gone.
- `MemberRenewal.period_billable?/3`: a period inside a minimum commitment
  is billed even after leaving.
- `MemberStatus` adds `former`; order former › leaving › cancelled › paused ›
  expired › overdue › unpaid › expiring. The last day is inclusive.
- `MemberStatus.standing/3` (`status`, `grace_until`, `access_until`,
  `outstanding_cents`, `unpaid_since`) is served to the member
  (`/me/billing` → `standing`) and to staff (directory row `standing`).
  `memberships.entitlement_grace_until` is stored with the entitlement
  snapshot.
- `DELETE /me/membership/leave` («Μένω στο box») is removed.
- Notification `box_membership_ended` (locked category) tells the member
  when staff end their membership.

Web:

- Εγώ › Πληρωμές: one dialog «Αποχώρηση από το …» listing what stays
  (package until, commitment, owed, following), the reason behind a link,
  «Αποχώρηση τώρα» and «Επικοινωνία με το box». Afterwards a card «Δεν είσαι
  πια μέλος του box» with «Γίνε ξανά μέλος box».
- The current subscription's status is the standing badge and line
  (`StandingBadge`), the same component staff see in the directory.
- Box: a former member sees «Δεν είσαι μέλος» and the package's last day;
  schedule, bookings and WOD stay; referral, announcements and extensions
  are hidden.
- Staff directory: a former member with nothing owed is hidden unless the
  status filter picks «Πρώην μέλος box». The staff leave form keeps only the
  reason.

## Consequences

- ADR-220 leavers are carried over by the migration (non-staff only).
- A member with no finance profile can leave too; nothing is kept or owed.
- Undo exists only for staff (a mistake); a member joins again.
