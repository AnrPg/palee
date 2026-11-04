# ADR-510: Pay items are either «Κάθε περίοδο» (automatic) or «Μία φορά» (one person, one period)
Date: 2026-11-04
Status: Accepted

## Context
ANR's audit of «Υπερωρίες και επιδόματα» (ADR-382), 2026-11-04. The catalogue's add dialogs read as if every item were recurring, but:
- an allowance «Μία φορά την περίοδο» (`per_period`) was never added automatically; someone had to add it by hand to each person in each period;
- overtime could only be computed from classes, so hours outside classes (a competition, a shift) had no place;
- a one-off allowance needed a catalogue type first, and the line dialog offered allowances for roles the person does not hold (the API then refused them);
- on a phone the nested «Κανόνες · Περίοδοι · Υπερωρίες και επιδόματα» switch folded into a dropdown that looked exactly like the Finance tabs dropdown above it.

ANR picked colour A and form B from the mockups (https://claude.ai/artifact/2kEjkkDcQEuZ24WpQGmAfj) and answered "fix it" on every finding.

## Decision
1. Every add dialog in the catalogue starts with a switch **«Κάθε περίοδο · Μία φορά»**, each with a one-line hint, and an explanation line under it. A box «Πώς δουλεύουν» above the catalogue explains both workflows and what the «περίοδος» is (the pay period opened in Οικονομικά › Αμοιβές coaches › Περίοδοι) with a link there (`?tab=pay&pay_view=periods`).
2. **Κάθε περίοδο**:
   - overtime: a rate per hour with a weekly threshold, computed from classes (unchanged);
   - allowance: `per_period` with a new `frequency` (`period` | `monthly` | `weekly` | `daily`, column `coach_pay_items.frequency`, NULL for every other item). The calculation adds it by itself to everyone holding one of its roles (lines `source_type: pay_item`): `period` pays the whole amount once per pay period; the others are prorated by days exactly like fixed pay (`Proration`).
   - A recurring allowance is never added by hand (`pay_item_id: added_automatically`). It can be taken off one person for one period: deleting its line records a row in `coach_pay_item_skips` (tenant table, RLS, unique per period, person and item), and recalculation honours it until «Επαναφορά» (`DELETE /coach-pay/periods/:id/skips/:skip_id`).
3. **Μία φορά**: one person, one open (draft) period.
   - overtime: hours × a saved rate, or a rate typed for the line; a reason is required. An overtime item **without** a weekly threshold is a one-off rate only (never computed from classes). People who manage settings can create such a rate from the form.
   - allowance: a saved per-occurrence allowance × times, or «Άλλο ποσό», which is a payment by hand (`ad_hoc`) unless «Κράτα το…» saves it as a per-occurrence allowance.
4. Lines added by hand group apart from computed ones (`manual:<kind>:<basis>`), so one-off overtime never merges into the computed overtime row and each can be removed.
5. Forms offer only the items whose roles the person holds (`GET /coach-pay/people` returns each person's pay roles).
6. `SegmentPicker` takes `level="sub"`: a nested switch folds into an Ink (`var(--text)` on `var(--bg)`) dropdown; the page-level one stays the Dojo fill. `data-segment-dropdown` names the level.

## Rationale
The two workflows answer different questions (a rule that runs by itself vs. a payment for one event), so the form asks it first instead of hiding it in a unit field. Automatic recurring allowances remove the per-person, per-period chore that the old wording promised but never did. Proration by days reuses the fixed-pay arithmetic, so a two-week period pays half a monthly allowance with no new rule.

## Alternatives Considered
- Two separate buttons per kind (mockup form A): more buttons on a screen ANR wants decluttered.
- A per-box definition of «περίοδος»: the pay period already is the box's choice; a per-allowance frequency (ANR's question) covers the remaining need.
- Deleting the auto line without a skip row: the next calculation would add it back.

## Consequences
- Migration `20270815100000_coach_pay_item_frequency_and_skips` backfills existing `per_period` allowances to `frequency: period`; from the next calculation they reach everyone with their roles. Boxes that used to add them by hand should check the next period.
- `coach_pay_item_skips` is part of coach pay's retained tenant data and of the personal data export (by `user_id`).

## Implementation Notes
- `Palee.CoachPay.Domain.Allowances.lines/6` builds the automatic lines; `PayItemPolicy.recurring?/1` decides the workflow.
- Web: `PayItemsCatalog` (switch, explanation, summaries), `OneOffLineForm`, `PayPeriodsView` («Όχι σε αυτή την περίοδο» / «Επαναφορά»).
