# ADR-552: «Γίνε μέλος box» on every box page
Date: 2026-11-07
Status: Accepted

## Context
ANR (2026-11-06) asked whether following a box found in the Feed search makes
the person a member. It does not: a follow (`community_follows`, target
`organization`) only brings the box's public posts into «Οι δικοί μου», its
open clubs into «Βρες» and the box into Connections › Boxes. Membership comes
from the member join link, an invitation or the staff. Yet the public box page
showed only «Ακολούθησε» (the filled, primary button), «Δοκιμαστικό» and a
message icon, so following looked like joining, and nothing on the page led to
becoming a box member (packages were linked only from the box website and the
desk-guest banner, ADR-272).

Mockups: `/mnt/project-files/milos/box-join/box-join-mockups-2026-11-07.html`.
ANR picked 1A and added: "there must always be a button «become a member» no
matter what, and it must be prominent".

## Decision
1. For a signed-in non-member and for a signed-out visitor, the page's main
   action is **«Γίνε μέλος box»**, full width, Spark. Below it, in one row:
   «Δοκιμαστικό», «Ακολούθησε» (outlined, `FollowButton quiet`) and the
   message icon. Box members keep «Μέλος box · Άνοιξε το club».
2. The button is always there and never a dead end. `GET /api/public/boxes/:slug`
   returns `joining: %{packages, join_link}` and the web
   (`components/box-page/join-box.ts`) leads to, in order:
   - the box's packages page `/b/<slug>/packages` when it lists packages people
     can buy or ask for (`OnlineSales.listed_packages/1`);
   - else the member join link `/join/<slug>` when it is on;
   - else the chat with the box (`/b/<slug>/chat?draft=member`, after sign-in
     when needed) with «Γεια! Θα ήθελα να γίνω μέλος. Πώς γράφομαι;» ready.
3. The box's own-domain website (standalone) keeps its own actions (ANR s3 A).

## Open
What happens when a non-member buys a package while the member join link is
off (today the sales page sends them to `/join/<slug>`, which is closed) is
question 2 of the same mockups, pending ANR's pick.
