# ADR-590: One way into a box: its page, from the feed and the club bar
Date: 2026-11-09
Status: Accepted. §2 and §3 built; §1 waits for the desktop box-page layout (same file)

## Context
ANR (2026-11-09) asked how followers reach a box's public page `/b/<slug>`:
tapping the box's bubble on Αρχική opened its club instead. On main
e6861f1d:
- The bubble is the club bar's (`ClubBar`), which lists only clubs: a box's
  club for its members and staff, plus joined open clubs. It always opens
  `/clubs/<id>`. A follower who is not a member has no bubble at all.
- The box page shows members «Μέλος box · Άνοιξε το club», but the club page
  has no way back to the box page.
- In the feed, a box's public post (staff speaking for the box,
  `AudiencePolicy`) shows the box name as plain text above the coach who
  wrote it. The box cannot be tapped.

Mockups: /mnt/project-files/milos/box-page-entry/box-page-entry-mockups-2026-11-09.html.
ANR picked Q1 A (Club tab first for members), Q2 A (same for everyone),
Q3 A.

## Decision
1. **One box page.** `/b/<slug>` is the box's only destination. Its members
   and staff get a «Club» tab, first and opened by default; everyone else
   opens on «Σχετικά». The club-bar bubble of the member's own box opens
   `/b/<slug>`. Open clubs keep `/clubs/<id>`.
2. **Box posts are headed by the box.** A public post in a box's club
   (`origin: club`, `audience: public`, club `kind: gym`) shows the box's
   logo and name on top, both linking to `/b/<slug>`, and «από <coach>»
   (linking the coach's profile) with the time underneath. The channel and
   «Καρφιτσωμένο» stay as a small line above. Same look for members and
   followers. Every other post keeps its author on top (`PostCard.boxVoice`).
3. **Followed boxes in the club bar.** After the person's clubs, one bubble
   per box they follow (accepted) and do not belong to, with a dashed ring
   in the accent, opening `/b/<slug>`. Read from the first page of
   `GET /api/me/following?type=organization`; unfollowing removes it
   (the `SOCIAL_KEY` invalidation refreshes the bar).

## Consequences
- No new endpoint; the bar reuses the follow list.
- e2e: community.spec «a followed box shows as a dashed bubble…».
