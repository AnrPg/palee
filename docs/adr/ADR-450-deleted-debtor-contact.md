# ADR-450: A deleted profile that still owes a box keeps a contact there until the debt is paid
Date: 2026-11-03
Status: Accepted

## Context
A profile that appears in a box's accounts is anonymised, not deleted (ADR-211), and money owed for
anything already used stays owed and is reminded until paid (ADR-220). After anonymisation the box saw
the debt under «Deleted account» with no name, no email and no phone, and the in-app payment reminder
reached nobody. The product owner (ANR, 2026-11-03) chose «Κρατάμε επαφή» over blocking the deletion
or leaving it as it was: GDPR art. 17(3)(e) lets the box keep what it needs to claim the debt, and the
right to erasure must not wait on a payment.

## Decision
- **`finance_debtor_contacts`** (migration `20270519000000`, per box and membership, forced tenant
  RLS): `display_name`, `email` (the login's), `phone_e164` (the box's SMS number, ADR-348), `locale`
  and `kept_at`. Nothing else about the person.
- **When.** The account-deletion sweep (`AccountDeletion.remove_profile`) calls
  `DebtorContacts.keep/1` before it forgets the SMS number and anonymises the profile. For each
  membership with an outstanding balance (`outstanding_balance_per_membership`, in that box's scope)
  one row is written. The sweep has no session scope, so the boxes come from
  `palee_deleting_profile_memberships(user_id)` (SECURITY DEFINER, pins only `search_path`), which
  answers only for a profile whose deletion is scheduled.
- **Staff see it.** «Οικονομικά › Εκκρεμότητες › Οφειλές» shows the kept name in place of «Deleted
  account», with «Ο λογαριασμός διαγράφηκε · η επαφή κρατιέται μέχρι να εξοφληθεί» and the email
  (`mailto:`) and number (`tel:`) (`kept_contact` on the row).
- **Reminder.** The daily `PaymentReminderJob` emails `:debt_reminder` (gettext domain `debts`, 12
  locales, origin `box`, no link since there is no account) to the kept email instead of the in-app
  notification. Without a kept email it sends nothing.
- **Release.** The same daily run first deletes the contacts of memberships that owe nothing any more
  (`DebtorContacts.release_settled/1`). A box purge deletes them with the box (Finance tenant data
  policy).

## Consequences
- A debtor's name, email and number stay with that box only, and only while the debt is open; Palee-wide
  the profile is anonymised as before.
- Palee stores no general phone number for members; the number kept is the box's SMS contact, when the
  box had one.
- Other staff screens (member list, profile) still show «Deleted account»; adding the kept name there is
  a read-side change on `DebtorContacts.labels/2`.
