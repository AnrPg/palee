# ADR-596: Box page on desktop (bento) and the featured package

- Status: accepted (ANR, 2026-11-09)
- Mockups: `/mnt/project-files/milos/box-page-desktop/box-page-desktop-mockups-2026-11-09.html`

## Context

On laptops and desktops the public box page (`/b/<slug>`) read as a long
column of text on the left with a small card on the right that often held a
single button, so the page looked left-heavy and dated. ANR picked layout C
(«bento»), actions beside the name with a slim bar on scroll, the cover
inside the page's width, the timetable as tiles with a day strip, and a box
chosen «Προτεινόμενο» package.

## Decision

Web (`PublicBoxView`, `BoxBento`, `AboutTab`, `SiteSections`):

- Desktop header: the cover sits inside the 1200 px page, rounded; logo
  (120 px), name and the actions in one row under it. Phones keep the
  edge-to-edge cover and the fixed action bar.
- The tab bar is sticky. On desktop, once the header scrolls away, it also
  carries the logo, the name and the main action («Γίνε μέλος box», or the
  club for members). The selected tab is the Spark pill only.
- `BoxBento`: two columns of rounded cards on desktop (7/12 wide, 5/12
  narrow). Each column keeps the owner's order, so a tall card never leaves
  a hole beside it. On phones the column wrappers are `display: contents`
  and CSS `order` restores the owner's order. A part with nothing to show
  renders nothing and its card is `:empty` and hidden.
- «Σχετικά» splits into parts (`intro`, `photos`, `clubs`, `rooms`, `facts`,
  `coaches`, `location`); `about` still means the first five for callers.
  The right column starts with the info card (map, address, hours); a
  single location's own card is hidden on desktop because the info card
  says it. Other tabs keep their list on the left with the info card right.
- Timetable: a strip of days (tabs), then the day's classes top to bottom in
  time order. Classes that start at the same minute share one row of fixed
  width, side by side. The next slot to start is outlined with «Επόμενο»,
  computed in the browser only (no server clock in the HTML).

API:

- `finance_settings.featured_package_id` (FK to `membership_packages`,
  `ON DELETE SET NULL`): one featured package per box by construction.
- `PUT /api/org/:slug/admin/package-audience/featured` `{package_id|null}`
  answers the package audience settings, which now include
  `featured_package_id`. Same permission as the audience settings.
- The public package lists mark `featured: true` on that package only when
  the viewer sees it (audience rules first, ADR-553).
- Web: «Προτεινόμενο στη σελίδα του box» switch in a package's advanced
  settings; the page lists the featured package first, as a dark card with a
  Spark «Προτεινόμενο» label.

## Consequences

- One more column in `finance_settings`; no backfill.
- The members' «Club» tab (ADR-590) slots into the same tab bar and tab panel.
