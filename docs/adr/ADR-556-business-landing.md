# ADR-556: palee.app/business sells Palee to boxes and coaches
Date: 2026-11-08
Status: Accepted

## Context
After the guest landing (ADR-555), ANR (2026-11-08) asked for a similar
landing page for business accounts, with its own marketing and selling
points to hook boxes, and asked to "go heavy with animations".

Mockups (options A, B, C and the hybrid):
`/mnt/project-files/milos/landing/business-landing-mockups-2026-11-08.html`.
ANR picked a **hybrid**: A is the core, with a subtle switch between Box and
Independent coach that shows coaches their own screens; «See how it works»
opens B's day timeline in an overlay, animated as in the mockup; a Box vs
Coach comparison table closes the page; managerial features (machine
maintenance, staff pay and allowances, cleaning schedule, stock, in-app ad
campaigns, partner offers, full accounting, analytics with insights and
pain-point detection) get their own section.

ANR's comments on the mockup also set:
- Wherever the myDATA connection is advertised, it says "if you choose;
  otherwise one-click export for your accountant", because automatic
  submission to the tax authority scares many owners.
- The free website and the free e-shop are huge selling points: a standout
  section plus their own stories on phones.
- Staff pay and allowances, cleaning, machines and stock are never shown to
  independent coaches.
- The ad animation must not cover the tile's text; the schedule tile shows
  two slowly filling classes.
- The bento has no holes at any screen size.
- The «For business» link on the athletes' landing sits apart from Sign in
  and Create account, spatially and in style.
- Phone story order for boxes: intro, free website, free e-shop, AI, timer
  on the TV, QR check-in, analytics, box club, running the business,
  payments, demo. Coaches: intro, free page, free e-shop, online
  programming, AI, analytics, coach's group, payments, demo.

## Decision
- New public route `/business` (`app/business/page.tsx`, in `PUBLIC_PAGES`
  for SEO). `?for=coach` opens the coach's side; the switch keeps it in the
  address with `history.replaceState`.
- `components/business-landing/content.ts` holds what each audience sees as
  pure data (tiles, management tiles, the day timeline, stories, comparison
  rows). The bento is 1, 2 and 4 columns with `grid-auto-flow: dense`;
  `gridHoles` simulates the packing and a unit test checks there are no holes
  for every audience at every size, and that coaches never get box-only
  tiles.
- `BusinessConsole` is a laptop that runs a box (or a coach's day) on a pure
  reducer (`console-state.ts`): seats fill, the waiting list moves, toasts
  arrive, takings count up. It stands still with reduced motion.
- `HowItWorks` is a full-screen `Dialog`: the step in view lights up, the
  line fills and, from tablets up, a sticky phone changes screen. The page
  behind is `inert` while it is open.
- Phones get stories through `StoryFrame`, a generic player extracted from
  ADR-555's `StoryPlayer`, which now wraps it. The athletes' stories gain a
  last story for owners and coaches that links to `/business`.
- Visuals (`BusinessVisuals.tsx`) are CSS animations with the `landing-`
  prefix in `globals.css`, all off under `prefers-reduced-motion`; colours
  only through theme variables.
- «Campaigns» are the existing promotion campaigns (Marketing › Box offers,
  `promotion_campaigns` with codes, shown to members in Payments › Offers when
  the box marks them visible). ANR (2026-11-08) pointed out they exist; the
  tile describes only that, with no «Soon». In-feed ads and ads to non-members
  nearby do not exist and are not advertised. (Seasons, ADR-167, are dated
  training programmes with places, not campaigns.)
- All copy is in the `BusinessLanding` namespace in the 12 locales, with
  ontology terms (Box, Independent coach, Class, Subscription package, Box
  club, Coach's group, Online programming, Branch, Front desk, Accountant,
  Cleaning staff, Day WOD, «At risk»). No invented figures or testimonials.

## Consequences
- Business sign-up still goes to the existing flow (`BUSINESS_SIGN_UP_HREF`);
  the owner card on the athletes' landing now points to `/business` first.
- `soon` on a tile stays available for a feature that is on its way.
- `npm run i18n:check` passes: numbers with units and one first name
  («Eleni · 3 km») count as shared values, `t.rich` keys and `@container`
  classes are not copy, and the brand words live in `branding/brand.ts`.
- e2e: `e2e/business-landing.spec.ts`.

## Amendment (2026-11-09, ANR's review)
- One contextual chip beside the logo on both landings (`landing/AudienceChip`):
  on the athletes' page «For business →», on the business page «For athletes
  →», on phones too. The separate «For athletes» link next to Sign in is gone.
- The Box / Independent coach switch sits in the middle of the business top
  bar (`grid 1fr auto 1fr`); «For:» and the long «Independent coach» show from
  xl up, «Coach» below. On phones it sits centred under the stories' header
  (`StoryFrame` `subheader`).
- Animated cards: the e-shop products are shrinkable columns with the picture
  inside, the price on one line and a round «+»; the cart badge lands after
  the tap. Console notices have their own strip under the classes (two at
  most) instead of covering them. Stock rows are name + «Low» over a full
  bar. Insight notes sit above the chart, not on its lines. The rotating hero
  word lays out only the current word, so no gap is left before the comma.
- Visuals know the audience: the coach's receipt, group, offer and partner
  coupon speak for the coach, not the box.
- The athletes' pillar cards have no emojis; a short accent line leads.
- Greek: «Ανεξάρτητος coach» (masculine) wherever it is the subject.
