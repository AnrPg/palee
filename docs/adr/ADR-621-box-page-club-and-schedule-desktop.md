# ADR-621: Box page «Club» and «Πρόγραμμα» tabs on desktop

- Status: accepted (ANR, 2026-11-10)
- Mockups: `/mnt/project-files/milos/box-page-club-desktop/box-page-club-desktop-mockups-2026-11-10.html`
- Builds on: ADR-590 (the club as the box page's «Club» tab), ADR-596 (bento desktop)

## Context

On desktop the «Club» tab of `/b/<slug>` stacked three levels of navigation
(the page's tabs, then oversized Ροή / Κανάλια / Events / Μέλη club buttons,
then filter chips), showed «Events» twice (page tab and club tab), floated an
unlabeled «+» in the middle, kept everything in a narrow left column with the
right half empty, and repeated «Μέλος του club». «Μόνο coaches» read like a
coaches' setting, though it only narrows the Ροή to posts written by
coaches. «Πρόγραμμα» showed one day at a time in the same narrow column, with
«Φίλτρα» alone inside a large empty card. The header kept «Μέλος box · Άνοιξε
το club» although the club is a tab, an icon-only message button, and a tall
empty cover above every tab.

ANR picked: Club A (feed + side column), one Events tab, «Γράψε κάτι στο
club…» over the feed, «Αναρτήσεις από coaches» inside «Φίλτρα», a low cover
outside «Σχετικά», a labelled «Μήνυμα» + share without the open-club pill, and
Πρόγραμμα S1 (the week in seven columns).

## Decision

Web only; no API change.

- `BoxClubTab` (new, `components/box-page`): one level of navigation.
  - Desktop (`lg`): two columns. Left: `ComposePrompt` («Γράψε κάτι στο
    club…», opens the usual compose sheet aimed at the club) and the Ροή
    (`ClubPosts`). Right, sticky: «Επόμενα events» (up to 3; «Όλα» opens the
    page's «Events» tab), «Κανάλια» (joined active channels; a click shows the
    Ροή of that channel, again shows all; «Όλα» shows the full channel list in
    the left column with «Πίσω στη ροή»), «Μέλη club» (faces + count; «Όλα»
    shows the list). Cards with nothing to show are left out.
  - Phones: a small Ροή · Κανάλια · Μέλη club switch over the same views.
  - The Ροή's events card shows on phones only (`ClubFeed eventsClassName`),
    since the side column lists them on desktop.
- `ClubPage` keeps `ClubSpace` for `/clubs/<id>` (open clubs, unpublished
  boxes) with its four tabs; its bodies are split out as `ClubChannels` and
  `ClubPosts` so the box page reuses them.
- Filters: «Μόνο coaches» is renamed «Αναρτήσεις από coaches» (12 locales) and
  lives in the «Φίλτρα» sheet only, everywhere `PostFilters` is used. On the
  box page the channel is also sheet-only, and the filters hide while the
  club has no posts and nothing narrows it.
- One «Events» tab: for the club's members and staff it renders
  `ClubEventsTab` (members-only events too, staff create there); visitors
  keep `BoxEvents`.
- Header: the desktop cover is `h-80` on «Σχετικά» (and the box's own
  domain) and a `h-36` strip on the other tabs. Members and staff get a quiet
  «Μέλος box» / «Staff του box» badge beside the area, and their actions are a
  labelled «Μήνυμα» plus a share button on desktop (the cover's share hides
  there). «Μέλος box · Άνοιξε το club» is removed from the header, the sticky
  bar and the phone bar; members get no fixed phone bar (their actions sit
  under the name). `BoxPage.memberOpenClub` is deleted.
- «Πρόγραμμα»: signed-in viewers get the full width. Desktop shows
  `WeekNav` (‹ range ›, «Σήμερα») with the filter chips in one row, then
  `WeekGrid`: seven day columns of tiles (time, class, coach, «Πλήρες» or
  places left, trial tag), past ones faded, today marked. Phones keep the
  week strip, the folded filters and the day list.
- Desktop vs phone layouts that differ in content use `useMediaQuery("(min-width: 64rem)")`
  so each control renders once (no duplicate labels for tests or screen readers).

## Consequences

- e2e `public-box-page.spec.ts`: the member test checks the compose prompt,
  the badge, the labelled message, no open-club pill and the single Events
  tab; the schedule test checks seven columns on desktop and the folded
  filters on phones.
- Unit: `WeekGrid.test.tsx`.
- The member's own booked class is not marked in the week (the public
  schedule API does not say which slots are yours); members book in their own
  Πρόγραμμα as before.
