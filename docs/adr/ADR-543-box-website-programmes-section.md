# ADR-543: «Προγράμματα» on the box website
Date: 2026-11-04
Status: Accepted

## Context
Board screen 4κ/4μ: the box's programmes as a section of its website (and a
menu link), up to three cards and «Όλα τα προγράμματα (N)», hidden when the
box sells no programme.

## Decision
1. A new section key `programmes` in `BoxSite.Domain.SiteSections`, after
   `packages` in the default order. Like `events` (ADR-388) it needs no
   setting: on by default, shown only when the box has a programme on sale
   (published, paid, with a version); existing sites get it appended to their
   order; the owner hides or moves it like any other section.
2. `GET /api/public/sites/:slug` answers `programmes: {items, total}`: the
   first three programmes on sale, newest first, as `PublicProgramme` cards
   (title, summary, price, weeks, sessions, level, `cover_url`, `reviews`,
   `main_equipment`, `minutes_per_session`), and how many there are. Empty
   when the section is not shown.
3. Each card links to the programme page (`/api/public/boxes/:slug/programmes/:id`).

## Consequences
- Programme titles are not part of the website translations (ADR-520) yet.
