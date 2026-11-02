# ADR-383: Money UI placement (card surcharge, coach pay) and no weekly booking limit
Date: 2026-11-02
Status: Accepted

## Context
Workstream W1 (money) had API support for the card surcharge (ADR-264, ADR-340), coach pay (ADR-341, ADR-382) and package purchase and booking rules (ADR-342), but no screens. The product owner chose one option per screen on the W1 mockup page (s1 to s7). For s7 they also decided that the package rules get no separate screen, and that the weekly booking limit is dropped.

## Decision
- **Card surcharge settings (s1 B):** Settings › Πληρωμές, under the online payments provider. A calm summary card, then a 3-step guide: Κανόνες (the law of the box's country, and its region where the law needs one), Ποσό (percent with the legal cap; fixed amount under «Προχωρημένα»; «στο κόστος» confirmation), Πού μπαίνει (channels). Card at the POS is off by default.
- **Member checkout (s2 A):** the surcharge is a line in the total («Επιβάρυνση κάρτας», or «Χωρίς επιβάρυνση»), above the pay button, which shows the total. Shown in package checkout and invoice payment.
- **Desk (s3 A):** `card_manual` is called «Κάρτα στο POS». When the box surcharges there, the receive-payment dialog asks «Τι κάρτα έδωσε;». «Δεν ξέρω» (default) adds nothing. The amount to type on the POS is shown large.
- **Coach pay (s4 A, s5 A):** Οικονομικά › «Αμοιβές coaches» tab with Κανόνες · Περίοδοι · Υπερωρίες και επιδόματα. Rules are sentences per person. A person without a rule stands out. Rules are edited in a side panel. A period shows one primary action per status (Έγκριση, then Εξαγωγή CSV), with «Υπολογισμός» and «Άνοιγμα ξανά» (with a reason) beside it. Statements open into their groups and lines. Gross is the default; net lines carry a «Καθαρά» mark in the info colour; totals read «Μικτά X · Καθαρά Y». «Μη φορολογητέο» starts as net. The overtime and allowances catalogue is in Settings and in the Finance tab. A staff member's profile shows their rules and statements. No payment can be hidden.
- **Own pay (s6 A):** `/admin/my-pay` «Οι αμοιβές μου»: the latest approved statement with its lines, gross/net and payslip PDF, then earlier periods. The staff home shows a card linking to it once a statement exists.
- **Package rules (s7):** no screen of their own. «Ποιος μπορεί να αγοράσει», «Αγορές ανά άτομο», «Προαπαιτούμενο», «Κρατήσεις ανά ημέρα» and «Ανοιχτές κρατήσεις» sit in the package wizard under «Προχωρημένα», grouped with «μόνο νέα μέλη» and «μία φορά».
- **No weekly booking limit:** `booking.weekly_limit` is removed from the package field catalogue, the booking terms, the API errors, the client and the UI. A weekly cap is the package's visits per week. Stored packages that still carry the key are read and saved without it (`PackageCatalog.drop_removed/1`).

## Rationale
Each placement is the option the product owner chose on the W1 board. The weekly limit duplicated visits per week. Two ways to say the same thing confused owners and produced two different error messages for one cause.

## Alternatives Considered
- A separate «Κανόνες πακέτου» screen (s7 B). Rejected by the product owner: the rules belong to the package and are rare.
- Keeping `booking.weekly_limit` hidden in the API. Rejected: a field nobody can set is dead weight, and old values would still block bookings.
- «Οι αμοιβές μου» under the member «Εγώ» tab, as the mockup draws it. Staff are sent from `/me` to `/admin`, so the page lives at `/admin/my-pay` and is reached from the staff home.

## Consequences
- Old stored `booking.weekly_limit` values stop applying from this release; the key disappears from a package on its next save.
- The desk's «outside the EEA» card is sent with country `ZZ`. This makes the API's EEA test false without naming a country.
- Member online checkout never knows the card before the provider's page, so it shows the surcharge the box would add only when the API quotes one for an unknown card. A saved-card picker is not built.

## Implementation Notes
- Web: `src/components/admin/payments/CardSurchargeSettings.tsx`, `src/components/payments/SurchargeTotal.tsx`, `src/components/admin/finance/payments/DeskSurchargeQuestion.tsx`, `src/components/admin/coach-pay/*`, `src/app/admin/my-pay/page.tsx`, the package wizard in `src/components/admin/finance/packages/package-ui.tsx`.
- API: `Palee.Scheduling.Domain.BookingLimits` counts the daily limit from the start of the class's gym-local day; the weekly branch and `booking_weekly_limit_reached` are gone.
