# ADR-638: «Γίνε μέλος» beside «Ακολούθησε»

- Status: accepted (ANR, 2026-11-10)
- Builds on: ADR-552 (ways to become a box member), ADR-590 (box page entry), ADR-221 (box search)

## Context

New people do not know the difference between following a box or an
independent coach and becoming its member. Lists that showed a box or a coach
offered only «Ακολούθησε». ANR asked for an electric-green (Spark) «Γίνε μέλος»
right next to every «Ακολούθησε» of a box or coach, as the more prominent of the
two, so the two read as different things.

## Decision

- API: `JoinBox.statuses(user_id, organization_ids)` answers, per box, where
  the viewer stands (`JoinRequestPolicy.viewer_status/3`): `staff`, `member`
  (current memberships, ADR-595: a box they left is not theirs), `requested`
  (an open «Ζήτα να γίνεις μέλος») or `none`. Two reads for a whole list: the
  person's memberships and their open requests across boxes
  (`JoinRequestStore.open_organization_ids/2`, the owner-read RLS policy).
- It is returned as `my_join` on `BoxSearchResult` and on followed boxes
  (`FollowedBox` in `GET /me/following?type=organization`), and as `join` on
  the door scan's visitor answer (null when the box has no published page).
- Web: `social/JoinBoxButton` (Spark) sits before `FollowButton`, which turns
  `quiet` (outlined) beside it. Members and staff see no button; a waiting
  request shows a quiet «Αίτημα εστάλη». Used in «Βρες» (box results),
  Συνδέσεις › Box and the door scan visitor card. The box page keeps its own
  `JoinBoxAction` beside «Ακολούθησε».
- The button opens `/b/<slug>?join=1`. `JoinBoxAction` reads the flag: once
  the packages this person sees are known it goes on to the way in (packages
  or the member join link); otherwise `AskToJoin` opens its sheet. There is
  one join flow, ADR-552's.
- Rows use `ui/rows` (`itemRowActions` wraps), so at 320px both buttons drop
  under the name instead of overflowing.
