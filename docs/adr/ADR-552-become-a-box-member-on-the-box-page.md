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
   - else, signed in, a request to the box («Ζήτα να γίνεις μέλος», decision 5);
     signed out, sign-in first (`/login?next=/b/<slug>?join=1`), which opens
     the request sheet on return.
3. The box's own-domain website (standalone) keeps its own actions (ANR s3 A).

4. **Buying makes you a member (Q2 A).** A package the box lists to everyone
   (`OnlineSales.listed_packages/1`) is an open door even when the member join
   link is off: «Συνέχεια» on the sales page or the desk-payment sheet calls
   `POST /api/memberships/join/:slug/package/:package_id`
   (`Application.JoinBox.for_package/3`), which admits the person as an active
   box member (`Organizations.admit_member/4`, `AdmitMember` command, reason
   `:purchase`) and then the purchase goes on as for any member. A package that
   is not listed answers 409 `package_not_for_sale`. Someone the box removed
   (an inactive membership) is not let back in by a purchase: 409
   `membership_unavailable`, with a way to write to the box.
5. **Asking the box (Q2 B).** `organization_join_requests` (tenant RLS plus an
   owner-read policy, one open request per person and box) holds «Ζήτα να
   γίνεις μέλος»:
   - person: `GET|POST /api/boxes/:slug/join-request`,
     `POST /api/boxes/:slug/join-request/cancel`; the button reads «Περιμένει
     έγκριση από το box» while a request is open;
   - staff with `manage_memberships`: `GET /api/admin/join-requests`,
     `POST /api/admin/join-requests/:id/accept|decline`, shown as a card at the
     top of Χρήστες only while someone waits;
   - notifications `join_requested` (staff), `join_request_accepted` and
     `join_request_declined` (person). Accepting admits with reason
     `:accepted_request`, which also lets a former box member back in.
   The policy is `Organizations.Domain.JoinRequestPolicy`; the store is a port
   (`JoinRequestStore`) with an Ecto adapter.

## Q2 decision
ANR picked "both a and b": buying a listed package admits (4), and the staff
approved request replaces the ready chat message as the button's last step (5).

## Programmes
Programmes are sold to box members only. The programme sales sheet's
«Γίνε μέλος box» for a non-member leads to the box page (its main action,
above), no longer to the member join link, which may be off.
