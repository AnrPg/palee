# ADR-770: Package changes for the members who already hold the package
Date: 2026-11-28
Status: Accepted

## Context
A purchase keeps a copy of the package's terms on the subscription (`price_cents_snapshot`,
`billing_period_snapshot`, `params_snapshot`). Editing a package therefore reached only new
purchases; recurring subscriptions were billed at the old price for ever. ANR asked for a
choice when saving (thread «Εφαρμογή αλλαγών πακέτου σε ενεργά μέλη», mockups
`/mnt/project-files/milos/package-changes/`), and picked 1A, rules as proposed, 3B, 4B and
the small decisions α–ζ.

## Decision
- **1A**: after «Αποθήκευση αλλαγών», when the package has holders and a change would reach
  them, a sheet asks «Ισχύει και για τα N ενεργά μέλη;» with «Και στα ενεργά μέλη» and
  «Μόνο στις νέες αγορές». Nothing is pre-chosen (no invented default). The server refuses
  the save with `package_terms_choice_required` (409) when no choice was sent.
  `POST /admin/finance/packages/:id/terms-preview` runs the save in a rolled-back
  transaction and returns, per change, when it reaches a holder, and the holders.
- **Rules** (`Palee.Finance.Domain.PackageTermChanges`):
  - more for the member (visits, class types, booking window, later cancellation, longer
    validity, renewal allowed…): **now**;
  - a price change (either way) and less for the member: **from the holder's next period**
    (**3B / 4B**: the very next period start, no waiting time; the member is told at once);
    a period already charged ahead keeps its terms (the one after it is taken);
  - billing period, joining fee, commitment, beneficiaries, seats, enrollment, coach,
    format, stacking, conversion: **never** for holders; who may buy (buyers, purchases per
    person, needed first, new members only, once per person): **purchases only**;
  - one-charge packages (visit pack, trial): price and less never; more now (a longer
    validity moves `ends_on` by the difference);
  - a shorter validity or «no renewal» is never taken from a holder;
  - a subscription with its own price (≠ the package's previous price) keeps it.
  - Name, description and tax category stay live, as before.
- **α** members hear `package_terms_changed` (bell + push): what applies now and from when.
- **β** the member's package (Εγώ › Πληρωμές) and the staff profile show the same
  «Νέοι όροι από …» and the history «Οι όροι ενημερώθηκαν στις …» (`term_updates`).
- **γ** a member who stopped renewing, is leaving or whose subscription ends before the
  next period never gets a deferred change (checked again on the day).
- **δ** a change that reaches nobody (name only, purchase-only terms) asks nothing.
- **ε** «Ποια είναι τα N μέλη» lists the holders; unticked ones are left out.
- **ζ** at most one pending update per subscription; a later change merges into it (newer
  value wins, a key applied now leaves it, a key back at the subscription's value drops).

## Implementation Notes
- Tables `finance_package_term_changes` (one row per saved change with holders) and
  `finance_subscription_term_updates` (per subscription: `now`/`next_period`,
  `pending`/`applied`/`superseded`, partial unique index on pending), RLS by tenant;
  migration `20271128120000`.
- Port `Palee.Finance.Ports.PackageTermsStore`, adapter `EctoPackageTermsStore`; the
  package save and the holders' updates run in one transaction.
- Pending updates apply inside `charge_subscription` right before the period they start
  is charged (so the charge uses the new price), and hourly in `SubscriptionChargesJob`
  for subscriptions without charges.
