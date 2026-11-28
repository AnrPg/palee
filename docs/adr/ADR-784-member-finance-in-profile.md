# ADR-784: A member's money managed from their profile
Date: 2026-11-28
Status: Accepted

## Context
Staff could see a person's money in three places that did not match: the «Οικονομικά» tab
of the staff profile (status, package and a long details block), the ledger's side panel
(`MemberPanel`, its own invoice cards) and the orphan page `/admin/finance/members/[id]`.
Paying an older or partly paid charge meant going to the ledger. ANR asked to manage a
person's finances from their profile (TO-DO 2026-11-28, mockups
`/mnt/project-files/milos/member-finance-profile/`) and picked 1C, 2 (one dated list with
filters), 2β, 3, 4, 5, 6 and 7.

## Decision
- One shared component, `components/admin/finance/member/MemberFinance.tsx`, with its pure
  logic in `member-finance.ts`. The profile tab and the ledger side panel (`compact`) both
  render it, so the picture is the same everywhere (pick 3). The side panel links to the
  profile tab.
- Summary: owed now (every open charge's balance), status, next charge (the day after a
  renewing period, at its price), credit balance. «+ Πληρωμή» (take_payments) and
  «+ Χρέωση για κάτι νέο» (manage_billing, `NewChargeDialog`, optionally «Χρέωση και
  πληρωμή τώρα») sit together (pick 6).
- Packages: every subscription still held, active or paused, each with its own
  «Αφαίρεση πακέτου…» (`RemovePackageDialog`); `InlineAssignPackage` assigns.
- Movements: one list, newest first, of charges, payments, refunds, gifts («Δώρο ή χάρη»)
  and granted credits (a forgiveness credit is shown once, as its gift). Each row is tinted
  in its kind's colour, no kind chips; filters show only the kinds present (pick 2).
- Every open charge (issued, partially paid, overdue) gets its own «Πληρωμή», which opens
  `ReceivePaymentDialog` on that charge with an empty amount and «Εξόφληση όλου · X»; the
  payment goes to that charge (pick 2β). Payments offer «Επιστροφή…» (manage_billing).
- Header (pick 1C): the staff profile's header shows the status and «+ Πληρωμή» only while
  something is owed, and never while the «Οικονομικά» tab is open (`showsHeaderPayment`).
- Rights (pick 4): whoever sees finance sees the tab; «Πληρωμή» and «Δώρο ή χάρη» need
  take_payments; refunds, new charges and voiding need manage_billing. No new capability.
- Social profile (pick 5): staff who see finance get one line «Μέλος του box σου» with the
  status and «Οικονομικά μέλους», never amounts (`StaffMemberLine`).
- Links (pick 7): «Το θέλω» rows, the package_requested and member_leaving notifications
  open `/admin/users/<id>?tab=finance`. Pending «Το θέλω» requests show in the tab.

## Consequences
- No new endpoint or table; everything reads `/admin/finance/members/:id` and the existing
  mutations.
- The general «+ Πληρωμή» still pays one charge at a time (no split across charges).
- `/admin/finance/members/[id]` is left as it was; it can be retired later.
- Replacing a package from the picker with `RemovePackageDialog`'s `replacement` comes
  with the package-change work on its own branch.
