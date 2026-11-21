# ADR-681: Free packages on the package page
Date: 2026-11-21
Status: Accepted

## Context
A package with a price of 0 (a free first week, a free trial) was never listed
anywhere public: `PackageSale.visibility/2` answered `free` and the staff switch
«Πωλείται online» was locked. ANR (2026-11-21) wants a box to show a free package
to anyone, members, followers, signed-in non-members and website visitors, when it
chooses to, as a marketing tool. Mockups
`/mnt/project-files/milos/free-packages/free-packages-mockups-2026-11-21.html`;
ANR picked 1A, 2A, 3A, small decisions α, β, γ yes and δ no.

## Decision
- **1A, one switch per package.** The package's existing switch reads
  «Φαίνεται στη Σελίδα πακέτων» on a free package. `PackageSale.visibility/2` now
  answers `free_listed` (listed) or `free` (kept off).
- **δ no, the same default as a paid package without online payments
  (ADR-291).** A free package is listed until the owner turns it off
  (`sold_online` or never chosen; add-on, shared and corporate packages never).
- **2A, «Το θέλω», the box activates it.** A free package is always asked for, with or
  without online payments: the public package lists carry `how` (`buy` | `ask`),
  `PackageRequestPolicy.requestable?/1` accepts a price of 0 and the
  `finance_package_requests_price_check` constraint is now `>= 0`. The staff
  queue shows one «Ενεργοποίηση» with nothing to collect. It calls
  `activate_unpaid`, which assigns the package with `billing: :none`, so no
  charge is issued and nothing is owed. `collect/4` has no money to record and
  refuses (a receipt of 0).
- **β, one class while waiting (ADR-633)** applies unchanged.
- **γ, the desk can still give any package by hand.** This is unchanged.
- **The person is told when it starts.** A request activated without the person at the desk
  (`activate_unpaid`, free or owed) sends the new notification
  `package_request_activated` (bell and push) to the person. Staff hear of a free
  request as «X θέλει το δωρεάν πακέτο Y».
- **3A, «Δωρεάν» in place of the price.** In the app it is an electric green tag
  (`PackagePrice`/`FreeTag`). On the box website it is the same tag in the website
  palette's accent (`.freetag`), because palettes own the website's colours (ADR-530).
  The period («τον μήνα») is not shown.
- **ADR-553 still decides who sees it.** The audience rules (Όλοι / Μόνο όσοι το
  έχουν / Κανείς, person exceptions) apply to free packages like any other.

## Rationale
Reusing the ADR-291/633 request flow keeps one way to ask for a package and
lets staff control who gets free packages (no farming with new accounts). The
listing rule stays in the domain (`PackageSale`), so every reader agrees.

## Alternatives Considered
1B (one box-wide switch) could not hide a staff-only free package. 2B (instant
claim) gave staff no control. 2C (chat only) was slower for everyone.

## Consequences
- Free packages that already exist and were never switched by their owner become
  visible on deploy (ANR's δ no).
- «N από M πωλούνται online» counts paid packages only.
- Migration `20271121170000_free_package_requests`.
