# ADR-370: Programme marketplace: boxes and coaches sell versioned programmes built from their own WODs
Date: 2026-10-31
Status: Accepted

## Context
CP-D4 (docs/plans/competitive-parity-and-beyond.md, P2): SugarWOD, BTWB and
TrainHeroic let athletes buy programmes written by known coaches. Palee's
edge is that a programme bought here is made of structured WODs (ADR-069,
ADR-270), so it arrives with scales, injury warnings and AI scaling from the
first day. The backlog asks to start with Palee's own coaches and boxes
selling (no publisher deals), and to import third-party programmes later.

What existed: seasons (ADR-167) sell a dated programme of WODs to a box's
members with a fixed start; the library (ADR-071/136); online payments
through each business's own provider (ADR-246..248); the store-app rule
that digital-only services are not sold in the apps (ADR-256).

## Decision
1. **A new bounded context `Palee.Programmes`** owns `programmes`,
   `programme_versions`, `programme_purchases`, `programme_deliveries` and
   `programme_reviews` (migration `20270601000000`; forced RLS, tenant
   trigger, composite `(id, organization_id)` keys). Money stays in Payments
   and Finance (ADR-371), WODs stay in Workouts.
2. **Writing.** A programme is a title, summary, level, goal, equipment,
   price (integer cents), listing and refund rule, plus a draft of days:
   `{day, workout_id}` within `draft_weeks` (1–52), at most 4 WODs a day,
   only published WODs of the same business.
3. **Versions are immutable.** Publishing freezes each WOD of the draft as a
   hidden library copy (`duplicate` → `publish` →
   `library_visibility: personal`) and writes version *n+1*
   (`programme_versions`, an `UPDATE` trigger refuses changes). A buyer
   keeps the version they bought; editing the original WOD or the draft
   never changes it. Title, price, listing and the refund rule apply to
   later buyers only (each purchase copies them).
4. **Where it is shown (`listing`).** `box`: the box's own public page
   (`GET /api/public/boxes/:slug/programmes[/:id]`) and its members.
   `marketplace`: also the cross-business catalogue
   (`GET /api/public/programmes`), read through the SECURITY DEFINER
   projection `palee_marketplace_programmes` (public fields of published,
   paid programmes of active businesses, with the published reviews'
   average). It pins only `search_path`, like ADR-154's `palee_around_*`.
5. **Preview.** Anyone sees the first `preview_days` (0–14) days by WOD
   title and summary and how many WODs each week has; the WODs open only
   after purchase.
6. **Reviews.** One per purchase, by the buyer, once the programme started:
   1–5 stars and up to 1000 characters, editable by the author. The seller
   never edits or deletes one; it may hide it with a reason (`abuse`,
   `personal_data`, `off_topic`, `spam`), which takes it out of the
   averages. A deleted account deletes its reviews.
7. **Staff API** (`/api/org/:slug/admin`): `programmes` (list, create, show,
   update, publish, archive, restore, purchases, reviews),
   `programme-purchases/:id/refund`, `programme-reviews/:id/moderate`.
   Capabilities: writing needs `manage_workouts`; publishing, archiving and
   moderating need `manage_packages`; buyers' list `take_payments` or
   `manage_billing`; refunds `manage_billing`. No new capability.

## Rationale
- Frozen copies make "what you bought is what you get" true without a
  second workout model, and reuse the existing execution, scaling and
  history paths.
- One context per concept keeps Finance and Workouts unaware of
  programmes; a projection function is the only cross-business read, so
  RLS stays forced on every table.
- Hiding instead of deleting reviews keeps them honest (the seller cannot
  curate the average by removal) while letting abuse and personal data go.

## Alternatives Considered
- **Programmes as seasons** (ADR-167): seasons have one start date, places
  and a crew channel; a programme starts when each buyer wants and sells
  without limit.
- **Referencing the live WOD** instead of a frozen copy: an edit or a
  re-publish (ADR-031 replaces the section tree) would change paid content.
- **A platform-level programme store with Palee as merchant**: Palee would
  hold money (licence, VAT, payouts); rejected in ADR-246 terms.
- **Importing third-party programmes now**: needs publisher agreements;
  left for later, the version model already fits imported content.

## Consequences
- A programme's WODs exist as hidden copies in the seller's library; the
  library's own views already skip `personal` copies.
- The catalogue lists businesses by name and slug; a business that does not
  want this keeps `listing: box`.
- UI waits for the approved mockup
  (`/mnt/project-files/milos/v31-mockups/w8-marketplace.html`).

## Implementation Notes
- Domain: `ProgrammePolicy`, `ProgrammeSchedule`, `ReviewPolicy`,
  `TenantDataPolicy` (retained 10 years with Finance, purge order 84).
- Store facade `Programmes.ProgrammeStore` (RepoContext), adapters
  `EctoProgrammeStore` and `EctoProgrammeCatalogue` (config
  `:programme_store`, `:programme_catalogue`).
- Application: `Programmes.Studio` (staff), `Storefront` (public),
  `Buying` (buyer), `Fulfilment` (payments), `Presenter`, `Terms`.
- The visitor's catalogue text is matched literally (LIKE wildcards
  escaped), at most 60 characters, 50 rows a page.
