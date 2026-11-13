# ADR-642: A box member when the purchase is real

- Status: accepted (ANR, 2026-11-13, «Με ενεργό πακέτο»)
- Amends: ADR-552 (buying makes you a box member), ADR-291 / ADR-633 («Το θέλω» and the one class while waiting), ADR-638 (`my_join`)

## Context

ANR saw «Μέλος box» on a box they had never joined, no «Γίνε μέλος» in «Βρες»,
and «Ανανέωση» in Box. Every screen read the same fact: their account was a
box member. ADR-552 admitted the person when they pressed «Συνέχεια» in the
buy or «Το θέλω» dialog, before any payment or request, so closing the dialog
left a member with no package; a declined or lapsed «Το θέλω» did too.

ANR's rule: you are a box member when you pay, or when you send «Το θέλω»
(so you see the classes and book your one class at once, then pay at the
desk). If the request is taken back, declined or lapses with nothing else,
you are not a member.

## Decision

- `organization_memberships.purchase_admission_at`: the person came in
  through a package and has no package yet. `PurchaseAdmissionPolicy` holds
  the rules; `Organizations.Commands.MovePurchaseAdmission` applies them in
  the person's own scope (the `AdmitMember` carve-out).
- «Συνέχεια» (`JoinBox.for_package`) gives the person **no role anyone sees**
  (revised the same day, ANR: «Επισκέπτης» is someone who really uses the
  box, not someone who opened the buy dialog). Stored as a marked row with
  `roles` `{guest}` only so the box's checkout and «Το θέλω» work for them;
  it is no member (not in `/memberships`, clubs or `my_join`, which answers
  `none`, so «Γίνε μέλος» shows) and no desk guest (`/memberships/guest-boxes`
  leaves marked rows out, no banner). The box's staff do not see them:
  `palee_organization_user_ids/2` and `palee_organization_member_roles/3`
  leave such rows out (migration `20271114100000`), so the directory, the
  desk's «Ποιος;», member counts and "is this person in the box" checks
  skip them. No `membership_activated`.
- Front desk making such a person a guest («Επισκέπτης», ADR-272) clears the
  mark in `palee_add_box_guest/2`: a real guest the staff see.
- «Το θέλω» (`PackageRequests.request/2`) makes a guest a member (marked) and
  announces `membership_activated`; a desk guest who asks becomes a member on
  the same terms.
- A package starting (online `fulfil_package`, the desk's «Είσπραξη» and
  «Εκκρεμεί πληρωμή», any `AssignFinanceMemberPackage`) promotes a marked
  guest and clears the mark. A desk guest sold a package by staff (no mark)
  stays a guest, as ADR-272 says.
- A request closing with no package (taken back, declined, lapsed) takes a
  marked member back to no visible role (the hidden marked row) unless something still holds them
  (`PackageRule.keeps_membership?/2`: another request waiting or a Finance
  profile). The one class while waiting is cancelled as before (ADR-633).
- Any other way in (join link, invitation, accepted join request) replaces
  the row and clears the mark; `JoinRequestPolicy.admission/2` lets staff
  accept a guest's «Ζήτα να γίνεις μέλος».
- Carried over (migration `20271113530000`): members since 2026-11-06 who
  came in by starting to buy (a request or an online package payment within
  ten minutes of joining) and have no Finance profile, no waiting request,
  no invitation and no accepted join request become marked rows with no
  visible role.
- Web: `JoinToBuy` calls `onJoined`, so the buy sheet and the «Το θέλω»
  dialog move on although the box is not in the person's boxes yet; «Το
  θέλω» and «Δεν το θέλω» refresh the person's boxes and clubs.

## Consequences

- «Μέλος box», `my_join`, Box and the club agree: a member is someone who
  paid, is waiting on «Το θέλω», or joined another way.
- Box lists say «Μέλος box» / «Staff του box» beside a box the person belongs
  to (commit b1ddace), so a missing «Γίνε μέλος» never looks unexplained.
- `Organizations.membership_standing/2` still answers `:member` for any
  active row, guests included (unchanged callers: chat, trials, referrals).
