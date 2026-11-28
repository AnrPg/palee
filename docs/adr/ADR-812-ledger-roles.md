# ADR-812: Every role of a client in the finance ledger, changed there
Date: 2026-11-28
Status: Accepted

## Context
Οικονομικά › Μέλη box had a «Τύπος» column. ANR asked (2026-11-28) to change
the "account type" from the ledger, to see all types when someone has several,
and what the difference between roles and account types is.

Palee has no account type: an account (`logins`) is an email and a password.
What a person is in a box are their **box roles**
(`organization_memberships.roles`, several at once). The «Τύπος» column showed
neither: it read `memberships.user_type_snapshot`, one value (member, athlete
or guest) written once when the finance profile was created
(`UpdateFinanceMember` used `put_new`), never updated when the roles changed,
and editable by hand on the old finance profile page. Staff roles never showed.
So the column could disagree with the person's real roles.

ANR picked from the mockups
(`/mnt/project-files/milos/ledger-roles/ledger-roles-mockups-2026-11-28.html`):
1 A and C (a small editor on the column and a bulk change), 2B (all roles),
3A (all roles as chips), 4A (one source of truth) and every small decision α–ε.

## Decision
- **One truth.** The column is «Ρόλοι» and reads the box roles; each ledger row
  carries `roles` (client roles first: member, athlete, guest, then staff). The
  finance profile's `user_type_snapshot` follows the roles: every role change
  (`SetMembershipRole`, whatever screen made it) writes the role the person now
  buys as (`MembershipPolicy.buyer_role/1`: athlete, member, then guest) in the
  same transaction; `UpdateFinanceMember` always derives it; the hand-edited
  select on the old finance profile page is gone; a migration heals every stale
  profile once. With no buyer role left the profile keeps its last value.
- **3A.** Every role is a chip: client roles filled, staff roles dashed.
- **1A.** For whoever may change roles (`grant_staff_roles`: owner, admin), the
  chips are a button that opens a popover with the roles that person may grant
  (the same hierarchy as the profile, ADR-219), others shown locked (2B).
- **1C.** A checkbox per row and «Επιλογή όλων» (the rows shown); a bar with
  «Αλλαγή ρόλων» opens a dialog where each role is «Ως έχει / Προσθήκη /
  Αφαίρεση». Each person keeps the roles the change does not name.
- **API.** `POST /admin/users/roles/changes/preview` and
  `POST /admin/users/roles/changes` take `{user_ids (≤50), add, remove}` and
  answer one result per person (`changed`, `unchanged`, `preview`, `refused`
  with a code). Each person goes through `ChangeMembershipRoles.set_roles/3`
  (seats, last owner, branch managers, hierarchy); one failing never undoes the
  others. The web sends larger selections in parts of 50.
- **α.** Dropping «Μέλος box» cancels future bookings only when the person is
  no longer a member or athlete; staying an athlete keeps them. The preview
  says how many bookings would be cancelled before «Αποθήκευση».
- **β.** When the change ends the person's member/athlete roles while a
  package runs, the preview says the package stays active until its last day
  (packages are never cancelled by a role change).
- **γ.** Without the right to change roles (e.g. Λογιστής) the chips are shown
  only, with no button and no checkboxes.
- **δ.** A ledger change must leave a buyer role (Μέλος box, Αθλητής or
  Επισκέπτης); the server refuses that person with `client_role_required`.
  Leaving the box stays its own action (ADR-595).
- **ε.** The column filter finds anyone holding a chosen role, whatever else
  they hold.

## Rationale
- One stored value that follows the roles, instead of two notions of "what a
  client is", removes a whole class of disagreement between the ledger,
  analytics (`ecto_kpi_store`, `filter_query`) and package retirement, which all
  read the snapshot.
- The bulk endpoint reuses the one role-change path, so every rule the profile
  enforces also holds for the ledger, for one person or fifty.
- Preview and change are two routes so the activity log records the change
  (`member.role_change`) and skips the preview.

## Consequences
- A member who becomes an athlete keeps their bookings (before, they were
  cancelled). Personal assignments still follow ADR-125.
- Staff roles can be given from the ledger; branches of a new staff role are
  still set on the profile (a branch manager's grant outside their branches is
  refused with the usual reason).
