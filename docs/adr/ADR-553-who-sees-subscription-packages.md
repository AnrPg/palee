# ADR-553: Who sees a box's subscription packages
Date: 2026-11-08
Status: Accepted

## Context
ANR (2026-11-08) asked for a box to choose who sees its subscription packages
on its page in Palee and on its website: everyone, nobody, or only the package
the viewer holds ("Your package is X. Contact the box to explore more plans").
The box also needed to choose per package and to show or hide packages for
chosen accounts. Before this, every listed package (`PackageSale.listed?`) was
shown to everyone. The website also had its own «Πακέτα» section switch
(`box_site_settings.hidden_sections`).

Mockups: `/mnt/project-files/milos/package-visibility/package-visibility-mockups-2026-11-08.html`.
ANR's picks:
- Q1 A, with ONE choice for both the Palee page and the website.
- Q2 A: the member's own package card, with a very subtle line under the
  green button and no button of its own.
- α–ε agreed, with δ «both».

## Decision
1. **One rule, in the domain** (`Finance.Domain.PackageAudience`). A package
   must already be listed for sale. Then the first step that has an opinion
   decides, and the more specific step always wins:
   1. a person exception on the package (`hide` wins over `show`);
   2. a person exception on the whole box (same);
   3. the package's own audience, unless it is `nil` («Όπως το box»);
   4. the box's audience: `all` «Όλα, σε όλους», `own` «Μόνο το δικό τους»,
      or `none` «Κανένα».

   Person exceptions apply only to a signed-in viewer.
2. **What «το δικό τους» means (α).** A person holds a package when they have
   a running (`active`/`paused`) subscription of it, or when it is the package
   of their latest subscription while they are still a box member (so they
   can renew it). Someone who holds two packages sees both.
3. **One choice for both places (Q1, β, γ).** `finance_settings.package_audience`
   applies to the Palee box page and to the website. The website shows what a
   visitor who is not signed in may see. The «Πακέτα» section of the website
   follows this choice and has no switch of its own: its row in Website › Look
   links to the setting. The migration turns a website that had hidden
   «Πακέτα» into `none` and removes `packages` from `hidden_sections` and the
   draft.
4. **Per package.** `finance_membership_packages.audience` holds `nil` (follows
   the box), `all`, `own` or `none`. The setting sits after «Πωλείται online» in
   the package panel, and a badge on the package row shows any package that
   does not follow the box.
5. **People (δ).** `finance_package_audience_exceptions` holds `user_id`,
   `effect` (`show`/`hide`) and `membership_package_id` (`NULL` means every
   package), one row per person and package. Staff pick box members first and
   then any Palee profile, searching by name or @handle. The exceptions stay
   folded until opened. The table is tenant scoped with RLS and is listed in the
   tenancy audit, the TenantDataPolicy and the PersonalData catalog.
6. **What someone cannot see, they cannot get (ε).**
   `Application.Payments.PackageAudience.check/3` guards buying online
   (`OnlineSales.package_for_sale`), asking at the desk
   (`PackageRequests.requestable_package`) and joining by a package
   (`JoinBox.for_package`). The error is the same as for a package that is not
   sold (`package_not_for_sale`). The front desk can always give any package.
7. **Member view (Q2 A).** Signed in, the page reads
   `GET /api/boxes/:slug/packages`, which answers for this person: `held` on
   each package, and `own_only` when other packages are kept for their
   holders. With `own_only`, the person's package shows «Ανανέωση», and under
   it, in small dim text, «Το πακέτο συνδρομής σου είναι X. Επικοινώνησε με το
   box για να δεις κι άλλα.». The «άλλα N» count is never shown (Q2 C rejected).
   When the person sees no packages, the page shows «Ρώτα το box για τα πακέτα
   συνδρομής» with «Επικοινωνία με το box». «Γίνε μέλος box» (ADR-552) then
   leads to the join link or to «Ζήτα να γίνεις μέλος», never to an empty
   page.
8. **Staff API.** The capability is `manage_packages`; reading also needs
   `view_package_catalog`. The routes are under `/api/org/:slug/admin`:
   - `GET|PUT /package-audience`
   - `PUT /package-audience/packages/:id`
   - `POST /package-audience/exceptions`
   - `DELETE /package-audience/exceptions/:id`

## Consequences
- Every place that lists or sells packages asks the same module. A new way to
  get a package must call `PackageAudience.check/3`.
- The public endpoint stays anonymous and cacheable. Personal answers come
  only from the signed-in endpoint.
- `own` on the website means that visitors who are not signed in see no
  packages there, and the section and its menu link disappear.
