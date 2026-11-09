# ADR-583: «Κοντά μου» looks further when nothing is near: wider radii, then the same town
Date: 2026-11-09
Status: Accepted

## Context
ANR (2026-11-09) saw «Κοντά μου» in Βρες empty and asked why Milos method,
in Volos like them, was missing: "if the list is empty, another rule should
fire, and see at least boxes in the greater area and then in the same
town/city".

What we found on main e6861f1d:
- Βρες › «Κοντά μου» lists open clubs only (ADR-143/154), not boxes.
- Γύρω μου finds a host only through a `facility_locations` row with a map
  pin (`palee_around_host_places`); a gym with an address but no pin, or
  with no location at all, is never found. Milos method had no location.
- Γύρω μου › Box never lists the person's own gyms (`AroundPlan.exclude_ids`).
- `search/3` already offers counts at wider radii (`wider`) when little is
  found; `kind/4`, which the «Κοντά μου» cards use, had nothing.

## Decision
1. `POST /api/around/search/:kind` takes `fallback: true`. When the first
   page (no cursor) finds nothing at the filter's radius, it looks further:
   - **Wider radii**: every rung of 10, 25, 50 km above the radius, nearest
     first. One `palee_around_counts` query finds the first rung with
     something; that rung's page is returned.
   - **The same town**: the origin's town (a city origin itself, a
     neighbourhood's city by `city_slug`, else the gazetteer city whose
     reach, its radius clamped to 6–20 km, covers the point) matched
     against `facility_locations.city` as typed, folded by
     `palee_town_key` (case, accents, spaces, final sigma), pinned or not.
     Boxes and open clubs only; events and posts have no town. A location
     without a pin has no distance and comes after the pinned ones.
2. Every kind page returns `reach: {scope: radius|town, radius_km, town,
   widened}`, so a screen can say where it looked.
3. A widened page is the first and last (`next_cursor: null`): a cursor
   pages the filter's own radius. The full list stays in Γύρω μου.
4. The person's own gyms stay out, by distance or by town; drafts and
   inactive gyms stay out as before. Same filters (tags, level, trial) apply.
5. Migration `20271110300000_around_town_fallback`: `palee_town_key`, an
   expression index on `facility_locations`, `palee_around_town_hosts`,
   and the definer functions `palee_around_town_boxes` and
   `palee_around_town_clubs`, mirroring `palee_around_boxes/clubs`.
6. The web «Κοντά μου» cards (Βρες, Εκδηλώσεις) ask for the fallback.
   How a widened list is labelled, what Βρες shows when no open club exists
   at all, and the empty «Ανοιχτά clubs» card go to mockups first
   (`/mnt/project-files/milos/nearby-fallback/`).

## Screens (ANR picks, 2026-11-09 20:47 UTC)
Mockups: `/mnt/project-files/milos/nearby-fallback/nearby-fallback-mockups-2026-11-09.html`.
- Ε1 B: a widened «Κοντά μου» card changes its title: «Έως 25 km», or
  «Στην πόλη σου · Βόλος» (`nearby.ts` `nearbyEyebrow`). Events too.
- Ε2 B: Βρες › «Κοντά μου» is hidden when no open club is found even in
  the town (a missing area still asks for one; errors still show).
- Ε3 B: Βρες › «Ανοιχτά clubs» is hidden when empty and nothing is typed;
  staff of a box (its gym club, role staff) see «Το <box> δεν έχει ακόμα
  ανοιχτά clubs» and «Φτιάξε ανοιχτό club» → Κοινότητα › Ανοιχτά clubs.
- Ε4 A: the staff admin Αρχική shows «Το box σου δεν φαίνεται στο Γύρω μου ·
  Πρόσθεσε διεύθυνση» (→ Ρυθμίσεις › Παραρτήματα) while no live branch has
  a town or a map pin (`BoxOnMapCard`, `boxFindableByPlace`).

## Consequences
- A gym still needs a location with at least its town to be found; with
  no location at all it is found only by name (ADR-221).
- `search/3` (the Γύρω μου page) keeps offering `wider` counts instead of
  widening by itself.
