# ADR-470: Show only what the business has switched on
Date: 2026-11-04
Status: Accepted

## Context
ANR (2026-11-04) saw Οικονομικά › Εκκρεμότητες offer «Αποτυχημένες χρεώσεις», «Ανταμοιβές σε εκκρεμότητα» and «Χρήσεις κωδικών προσφοράς» at a box with no online or card payments, no referral programme and no promotion, and Ρυθμίσεις › Χώροι show the «Παράρτημα» picker and the «Εμφάνιση κάτοψης στα τμήματα» toggle at a box with no branches and no floor plan. The rule: anywhere in the UI, if something is not activated for this gym, branch or solo coach, do not show it.

Each screen used to decide on its own (or not at all): `online_payments` flags on a few public payloads, `moduleEnabled` for the corporate tab, `showsAppliesTo`/`hasSeveralBranches` for some branch pickers, nothing for referrals, promotions, perks or saved-card autopay.

## Decision
One answer for every screen:

* **Domain** `Palee.Organizations.Domain.BusinessFeatures` (pure): the feature keys and the rules that turn facts into `%{key => boolean}`. Keys: `online_payments`; per purpose `online_packages`, `card_autopay`, `online_drop_in`, `online_shop`, `online_personal_training`, `online_programmes` (ADR-260 options on an active account); `referrals` (an active programme); `promotions` (an active, running campaign with an active code); `perks` (a published perk); `trials`; `branches` (two or more active branches); `floor_plan` (an uploaded plan); `module_<key>` (ADR-098 package modules). A missing fact counts as off. A branch filter narrows promotions and floor plans; everything else is business-wide.
* **Application** `Palee.Application.BusinessFeatures.status/2` reads one fact per feature through each context's public API.
* **API** `GET /api/org/:slug/me/features[?location_ids=…]` (tenant member scope): booleans only, so any member may read it.
* **Web** `lib/business-features.ts` (pure: `featureOn`, `showsWork`) and `lib/use-business-features.ts` (`useBusinessFeatures({ slug?, locationIds? })`, `useFeatureAtAnyBusiness`), cached per business and filter (`FRESHNESS.reference`).

Rules every screen follows:
1. Loading counts as off (nothing appears and then vanishes); an unreadable answer counts as on (a network blip never hides work).
2. A work list (queue chip, alert, KPI, history) stays while it still holds rows, even after its feature was turned off: owed rewards or failed charges are still owed.
3. The place where a feature is switched on always stays (Οικονομικά › Προσφορές/Συστάσεις, Online πληρωμές settings, «Προσθήκη κάτοψης»).
4. An action that needs a missing feature offers to set it up instead of an empty picker («Προσθήκη χώρου» without a plan shows «Προσθήκη κάτοψης»).

Applied in this change: Εκκρεμότητες chips (`offeredQueues`), the pending-rewards panel of the finance overview, the referral-approvals KPI of the staff home, the referral columns of Οικονομικά › Μέλη, promotion redeem panel and history on the member finance profile, «Συστάσεις» in Εγώ (any of my boxes), the saved-card autopay switch, Χώροι (no branch picker, eyebrow or per-branch groups with fewer than two branches; no class-plan toggle or plan picker without a plan), and Box screens' «where» with one branch.

## Rationale
One server-side source of truth keeps the activation rules next to the data they read and testable without a browser; one hook keeps every screen consistent and cheap (one cached read per business).

## Alternatives Considered
* Each screen reading its own sources (payment account, programmes, campaigns …): duplicated rules and many requests per page.
* Adding the flags to `/api/memberships`: every membership of every person would pay for reads only staff screens need.
* Hiding server-side in each list endpoint: the screen still needs to know to hide the chip, KPI or toggle.

## Consequences
* New optional features add a key in the domain module, a fact in the application module, and use `useBusinessFeatures().on(key)` / `.shows(key, pending)` in the screens.
* e2e stubs that answer `{}` for unknown routes get every feature off; specs that need one on stub `**/me/features**`.

## Implementation Notes
* `branches` mirrors `hasSeveralBranches` on the web (two or more non-archived locations), which the existing branch filter and «Ισχύει για» pickers already used.
