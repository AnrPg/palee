# ADR-641: Coaches in full, their profile or bio, and the box's website link

- Status: accepted (ANR, 2026-11-13)
- Builds on: ADR-142 (public box page), ADR-554 (profile «Λίγα λόγια»), ADR-530 (box website), ADR-354/398 (own domain)

## Context

On `/b/<slug>` the «Coaches» card cut long names («Xristoforos ri…») and the
coaches were not clickable. ANR asked for whole names, wrapped; a click opens
the coach's profile, or a page with their bio when there is no profile to
open; and a link to the box's website, Palee's or the box's own domain.

## Decision

- Coach names wrap (`overflow-wrap: anywhere`), never truncate
  (`box-page/BoxCoaches`).
- Signed-in viewers: each coach is a link to `/people/<id>` (every coach has
  a Palee account; a private account shows its locked profile).
- Visitors without an account, and the box's own domain, have no profile to
  open (`/people` needs sign-in). The coach opens a sheet with photo, name,
  what they teach and their «Λίγα λόγια». A sheet, not a route, because
  `/b/<slug>/coaches` is already the website's «Coaches» page.
- `PublicBoxCoach.bio`: `community_profile_cards` is readable only by
  signed-in sessions, so `palee_public_bios(uuid[])` (SECURITY DEFINER,
  migration 20271113500000) returns the bio only for accounts that are public
  (`palee_user_is_public`). Private accounts never show their bio outside Palee.
- Website link: under the box's name, beside the area, «Ιστοσελίδα» with a
  globe icon, only when the website is on (`site` present). The own domain
  shows its host and opens it; otherwise it opens `/b/<slug>?site=1`, which
  makes `SiteAudience` show the website even to a signed-in member (who
  otherwise gets the app's page at that address). Opens in a new tab.

## Consequences

- One more read on the public box page (one SQL call for all shown coaches).
- The website templates' own coach grid is unchanged.
