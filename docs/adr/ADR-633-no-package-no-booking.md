# ADR-633: «Χωρίς πακέτο, χωρίς κράτηση»: nobody slips the desk payment
Date: 2026-11-10
Status: Accepted

## Context
With «Το θέλω» (ADR-291) a person asks for a package and pays at the front desk. Before this, nothing stopped them from booking classes in the meantime: someone new to the box had no Finance profile, and `entitlement_enforcement_mode` defaults to `observe` (no settings screen), so a missing profile let every booking through. Someone could press «Το θέλω» and keep booking without ever paying. Staff also got no notification of a request, could not decline it, and a manual «Δωρεάν» or «Δοκιμή» status opened access with no end.

The product owner asked (2026-11-10) for "a safe and robust way to make sure that no members slip the payment … with the highest possible level of automation", and picked from the mockups `desk-pay-request-gaps-2026-11-10.html`:
- 1A: a notification with the actions (bell and push) to the staff who take payments.
- 2: «Απόρριψη» with a required reason, and the member is told. «Ενεργοποίηση τώρα»: yes, followed by «Εισπράχθηκαν X €» or «Εκκρεμεί πληρωμή».
- 3A: anyone without a package is locked out of booking if the box sells packages. 3β: one class is allowed before staff activate. 3γ: those already training get a 14-day grace automatically, and staff see a list.

## Decision
- **The rule** (`PackageRule.check_booking/4`, inside `SubmitBooking.write/4` before the visit is reserved):
  - It applies to a client or guest of a box whose `finance_settings.package_rule_since` is set.
  - A person with no Finance profile is refused with `finance_package_required` (403).
  - A person with a profile is judged by their package and debts as before. «No package», «ended» and «overdue past the grace days» already refuse.
  - The rule does not apply to staff, to the platform's admins, or to staff placing someone (`PlaceMemberInClass` passes `package_rule: false`).
- **One class while waiting**:
  - It is allowed while the person's first «Το θέλω» waits, and once per person and box. It is counted on the request (`first_class_at`, `first_class_scheduled_class_id`).
  - A unique partial index lets only one booking take it, even when two arrive at once.
  - Cancelling that booking does not give the class back. A booking that fails after the class was taken does give it back.
  - When a request is declined, lapses or is cancelled, the person's upcoming bookings are cancelled (`end_waiting/2`). This happens only if they still have no profile and nothing else waits.
- **Starting by itself** (`PackageRule.daily/2`, from the daily `SubscriptionExpiryJob`, before the entitlement refresh):
  - The rule starts the first day the box has an active package, and stops when the box has none.
  - At the start, every client or guest without a profile gets a 14-day `free_access` from the system. So does anyone held in by a hand-set «Δωρεάν»/«Δοκιμή» status with no end.
  - That grant is an ADR-612 ledger row with `actor_id` empty, `actor_roles = ["system"]` and the reason `package_rule_rollout`. A placeholder status becomes plain `active`.
  - Each person gets `package_rule_grace`. The staff who take payments get `package_rule_started` with the count.
  - After the 14 days, the daily refresh and `RevokeAccess` end access and cancel upcoming bookings, as for any ended access.
- **Staff**:
  - Each new request sends `package_requested` (bell and push) to everyone with `take_payments`. It links to `?tab=queues&queue=awaiting`, where each row has «Ενεργοποίηση» and «Απόρριψη».
  - «Ενεργοποίηση» › «Εισπράχθηκαν X €» is the ADR-291 collect. The desk must pick the payment method, because nothing is pre-chosen.
  - «Ενεργοποίηση» › «Εκκρεμεί πληρωμή» (`POST …/package-requests/:id/activate-unpaid`) assigns the package from today at the price the person was shown, with its charge issued now (ADR-274 `billing: :now`). The box's payment reminders, grace days and lock then follow the debt by themselves.
  - «Απόρριψη» (`POST …/:id/decline`) requires a reason of 1–500 characters. The request is closed as `declined`, the person gets `package_request_declined` with the reason, and their upcoming class while waiting is cancelled.
  - `GET /admin/finance/package-rule` lists the people on the rollout's 14 days, with their last day and whether they have a package now.
- **The member**:
  - `GET /me/package-rule` says whether the rule holds for them, whether a request waits, and whether the one class is still free.
  - A refused booking offers the box's packages, the same way a missing package already did, or explains how to get one.
- **Statuses by hand**: staff may set only `active`, `paused`, `expired` or `cancelled` (`MemberStatus.settable/0`). Free access always has a last day now, through «Δώρο ή χάρη». Overrides set earlier stay readable.

## Rationale
- Gating on "no profile" reuses everything that already judges a profile: the package, its allowances, debts and grace days. Giving everyone a profile would have meant a new placeholder status that opens or closes access.
- A box-level start date, set by the daily run, makes the rollout happen exactly once per box. It also works when a box adds its first package later, and nobody has to flip a setting.
- The rollout's grants go through the ADR-612 ledger, so the lineage (who, when, why, until when) is the same as for staff grants.

## Alternatives Considered
- Switching `entitlement_enforcement_mode` to `enforce_all`: rejected. It would also change WODs, programming and plan checks everywhere at once, and it has no exception for one class.
- A booking credit row per person: rejected. The request already exists and holds the person and the box. A unique index on it gives "once per box" without a new table.

## Consequences
- In a box that sells packages, a client who never had a profile can no longer book by default. Staff can still place them.
- A guest without a profile is gated like a client.
- The rule takes up to a day to start after a box's first package, because the daily run starts it.

## Implementation Notes
- Migration `20271113410000_package_rule`:
  - adds `finance_settings.package_rule_since`;
  - adds `first_class_at`, `first_class_scheduled_class_id` and `decline_reason` to `finance_package_requests`;
  - adds the status `declined`, with a check that a declined request has a reason;
  - adds `finance_member_benefits_actor_check`, so `actor_id` may be null only for `{system}`;
  - adds the four notification types.
- Telemetry `[:palee, :finance, :package_rule, :started]`. Log lines: `package_rule_first_class`, `package_rule_refused`, `package_rule_started`, `package_rule_stopped` and `package_rule_rollout_failed`.
