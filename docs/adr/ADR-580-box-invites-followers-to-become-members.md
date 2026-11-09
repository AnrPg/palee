# ADR-580: A box invites its followers to become box members
Date: 2026-11-09
Status: Accepted

## Context
ANR asked whether a box can invite the people who follow it to become
subscribed box members, one at a time or many at once. Nothing existed:
following a box is instant and the box saw only how many followed it
(`public_box.ex`), never who; staff invitations went only by email
(ADR-209); and a follower could only join on their own from the box page
(ADR-552).

ANR picked from the mockups
(`/mnt/project-files/milos/follower-invites/follower-invites-mockups-2026-11-09.html`,
2026-11-09): C (one person and many at once, in one list), followers who
are box members never listed; Q1 B (a card at the top of Χρήστες); Q2 B
with the opt-in on by default and changeable in the settings, and no
notice or card telling people they are now visible ("that is the normal,
expected thing"); Q3 every tag (Πρώην μέλος, Δοκιμαστικό, Εστάλη, Δεν θέλει
προσκλήσεις; open join requests stay in the join requests); Q4 an optional
message, an optional featured package and an optional trial, with «Γίνε
μέλος» leading to the ADR-552 way in; Q5 notification, push and a message
from the box in Μηνύματα; Q6 the same person again after 90 days.

## Decision
1. **Who is listed.** People who actively follow the box, who have not
   turned «Δέχομαι προσκλήσεις από box που ακολουθώ» off
   (`community_social_settings.box_invites`, default on), who are not box
   members (an active membership with a role other than guest), and whose
   «Ζήτα να γίνεις μέλος» is not open. Tags: former box member (suspended
   or revoked membership), did a trial (`scheduling_trial_requests`), the
   latest invitation (sent, with when the box may invite again, or
   declined). Worked out by the SECURITY DEFINER functions
   `palee_box_followers` and `palee_box_follower_counts`, bound to
   `app.organization_id`, because follows and settings are personal rows.
2. **Χρήστες card** (`manage_memberships`): shown only while at least one
   listed follower may be invited now; «Δες τους» opens the list with the
   filters Όλοι · Δοκιμαστικό · Πρώην μέλη, «Προσκάλεσε» on each row and a
   check box per row for many at once (up to 200 per send).
3. **One invitation** (`organization_follower_invites`): optional message
   (≤500 characters), optional package (only one the box lists to
   everyone, ADR-553), optional trial (only while the box takes trials).
   It becomes a `follower_invited` notification (bell and push, category
   Clubs & κοινότητα, opening the box page) and the same words as a
   message from the box in the person's Μηνύματα › Box. That message is
   sent with `notify: false` so the person hears once.
4. **The person** sees the invitation on the box page above «Γίνε μέλος
   box»: the box's words, the featured package if they still see it,
   «Γίνε μέλος» (the ADR-552 action), the trial button when offered, and
   «Όχι, ευχαριστώ», which declines every open invitation from that box
   and keeps the box from inviting them again.
5. **Rules** (`Organizations.Domain.FollowerInvitePolicy`): 90 days
   between invitations to the same person, never after a decline, 200 per
   send, 500 characters.

## Rationale
Reusing ADR-552's «Γίνε μέλος» keeps one way into a box (packages, the
join link or a staff-approved request), so an invitation can never lead to
a dead end. The list is computed in SQL so a box of thousands of followers
pages cheaply, and the visibility rule sits in one bound function rather
than spread over RLS policies on personal tables. The box's message rides
on the existing box thread (ADR-282), so a follower's answer reaches the
shared inbox like any other.

## Alternatives Considered
- A Χρήστες tab or a source inside «Πρόσκληση πελατών» (Q1 A, C): ANR
  preferred the card, which only appears when there is someone to invite.
- Names visible to every box with a one-time notice (Q2 A) or never
  visible (Q2 C): rejected; the notice would be clutter (ANR).
- Email invitations to followers: followers' addresses are theirs; the
  app's own channels reach them.

## Consequences
- Followers who keep the switch on are visible by name to the staff of
  boxes they follow who hold `manage_memberships`.
- The person's box thread can now start from the box's side for a
  follower (`GetOrCreateMessagingThread.for_invited_follower/3`).

## Implementation Notes
Migration `20271110100000_box_follower_invites`. API:
`GET /api/org/:slug/admin/follower-invites/summary`,
`GET|POST /api/org/:slug/admin/follower-invites`,
`GET /api/boxes/:slug/follower-invite`,
`POST /api/boxes/:slug/follower-invite/decline`. The privacy switch is
`box_invites` on `PUT /api/me/social/privacy`.
