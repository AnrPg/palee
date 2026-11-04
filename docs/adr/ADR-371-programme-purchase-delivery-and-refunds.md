# ADR-371: Buying a programme: the seller's provider, Finance lineage, scheduled WODs, withdrawal and refunds
Date: 2026-10-31
Status: Accepted (amended 2026-11-03: start request only inside the 14 days; hourly sweep; screens)

## Context
ADR-370 lets a business sell programmes. Palee must not hold money
(ADR-246), every sale needs its receipt or invoice (ADR-262), the revenue
must be traceable (ADR-190/192), and a programme is a service bought at a
distance by consumers (Directive 2011/83/EU). Programming a person needs a
grant (ADR-225). The store apps may not sell digital-only services
(ADR-256).

## Decision
1. **Who buys.** A signed-in person inside the seller's business
   (`/api/org/:slug/me/...`, `tenant_member`); joining through the box's
   join link comes first. A first purchase creates the buyer's membership
   like a package bought online (ADR-248).
2. **Paying.** `POST /me/programmes/:id/buy` writes a `pending_payment`
   purchase (idempotent per key; at most one active purchase of a
   programme per buyer) and opens a checkout on the seller's own provider
   account with the new purpose **`programme`** (`IntentPolicy`, the
   `payment_intents` check rewritten from its current definition, and the
   «Τι πληρώνεται online» switch `programmes`, ADR-260). Nothing is
   delivered before the provider confirms the money. Payouts and fees stay
   the seller's: Palee never handles the money.
3. **Fulfilment** (`Programmes.Fulfilment`, called by
   `Payments.FinanceFulfilment`, retried and idempotent per intent):
   membership → Finance sale `record_stream_sale` with stream `other`,
   `source_type = programme_purchase`, `source_id = purchase`, method
   `online` → the fiscal document (ADR-262) → purchase `active` → each
   version day assigned to the buyer on `starts_on + day` from the later
   of the start and today (`Workouts.assign_workout`), recorded in
   `programme_deliveries`. A reported amount different from the price is
   never delivered (`amount_mismatch`).
4. **The purchase is the grant.** Like a season (ADR-167), buying the
   programme is buying its WODs: delivery does not go through
   `AuthorizeProgramming` (ADR-225), and the grant covers these WODs only.
5. **Start date.** Today up to 60 days ahead (`RefundRules.check_start`).
6. **Withdrawal and refunds** (`RefundRules.quote/3`, the larger wins):
   - **the law**, where the seller's fiscal country is in the EU, EEA or UK
     (unknown counts as yes): within 14 days of buying, the price less the
     part already provided (days since the start over all days). A start
     date inside those 14 days requires the express request to start
     (`start_now`, text versioned and hashed into `withdrawal`, art.
     14(3)/16(a)); a later start needs none, since nothing is provided before
     the right ends (amended 2026-11-03, mockup W8 s5 A);
   - **the seller's rule**, copied onto each purchase: `before_start` (full
     refund until the start date, the default), `withdrawal_only`, or
     `pro_rata` (the days not yet reached, until the end).
   `POST /me/programme-purchases/:id/withdraw` refunds through the provider,
   ends the purchase (`withdrawn`) and removes the future WODs
   (`Workouts.remove_athlete_from_assignments/4`, new). Staff refund any
   part of what is left (`POST /admin/programme-purchases/:id/refund`); a
   full refund ends it (`refunded`) and removes future WODs. Every refund
   is a Finance reversal of the stream payment plus a credit note.
7. **Store apps.** A programme has only digital services, so the apps never
   offer the purchase (ADR-256 point 2); `canBuyHere` gains the item kind
   `programme` → web only.
8. **Personal data.** Purchases, deliveries and reviews are in the GDPR
   export (ADR-267 catalog). An account deletion keeps purchases without the
   person (Finance retention) and deletes their deliveries and reviews.

## Rationale
- The stream sale path already gives receipts, credit notes, lineage and
  idempotency; programmes need no new Finance concept.
- A refund rule copied at purchase is what the buyer agreed to.
- Treating a programme like a service with proportional withdrawal is the
  consumer-safe reading; see the open question below.

## Alternatives Considered
- **Art. 16(m) (digital content: no withdrawal once supply began with
  consent):** lets sellers refuse refunds from day one, but whether a
  dated, coached programme is "digital content" or a "digital service" is
  for legal review; the proportional rule is the safer default and the
  seller's own rule can only add to it.
- **Package with the online-programming channel:** would grant programming
  of any WOD by staff, not this programme, and mix recurring billing in.
- **Selling in the apps through In-App Purchase:** Palee would resell and
  hold money (ADR-256 rejected it).

## Consequences
- Programme revenue shows as stream `other` with its source; ADR-192
  reports can refine it by `source_type` without a migration.
- The wording of the start request and refund rules is a draft for legal
  review (`Programmes.Terms`). The buyer-facing terms were drafted on
  2026-11-03 as the «Προγράμματα προπόνησης» section of `/terms`
  (`legal.terms.programmesTitle` and `programmesBody1..5` in all 12 locales),
  with the reasoning and the lawyer's list in
  `docs/research/legal-terms-v3.2-2026-11-03.md`.
- An hourly sweep (`Programmes.Sweep`, `ProgrammeSweepJob` at :29) marks
  purchases `completed` after their last day on the seller's clock, and
  cancels `pending_payment` purchases older than a day whose checkout never
  opened or whose payment failed, was cancelled or expired. An open or
  succeeded payment is never cancelled under it (amended 2026-11-03).

## Implementation Notes
- Domain: `PurchaseLifecycle`, `RefundRules`.
- `programme_purchases.payment_intent_id` is unique; the fulfilment finds
  the purchase by intent or by `purpose_id`.
- Telemetry: `[:palee, :programmes, :created | :published | :archive |
  :restore | :refunded | :withdrawn]`.

## Amendment 2026-11-03: screens (ANR picked the recommended options of `w8-marketplace.html`)
- **Buy sheet (s5 A):** on the programme page, one sheet with the start date
  (ui/DateInput, today to +60 days), the request-to-start box only when the
  start is inside the 14 days and never pre-ticked, the refund rule's text,
  the total with VAT and «Πληρωμή στο <box>». A visitor signs in or joins
  the box first (same path as packages, ADR-248); the store apps show no
  buy button and no link to buy on the web (ADR-256 wins over the mockup's
  «Άνοιγμα στο palee.app»).
- **Member (s6 A):** the WODs are ordinary assignments in Box; a «Τα
  προγράμματά μου» card in Box › Σήμερα shows week, day and progress, and
  «Λεπτομέρειες» (`/box/programmes/:id`) lists the next WODs, the review
  (after the start) and «Υπαναχώρηση» with the amount shown before the
  button.
- **Staff (s7 A):** tabs «Αγορές» (table, a side panel with the suggested
  refund) · «Κριτικές» (hide with a reason, show again) · «Εκδόσεις».
- Open questions answered with the recommendations: withdrawal stays
  pro rata with the express request; no Palee commission; a buyer from
  another box joins it as a member without a package; earlier buyers keep
  their version.
