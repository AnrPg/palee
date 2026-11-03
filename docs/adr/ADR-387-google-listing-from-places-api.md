# ADR-387: The box's Google listing from the Places API, refreshed daily
Date: 2026-11-02
Status: Accepted

## Context
ANR's final W4 decision (s7): use the Google Places API with a Palee-owned
server key; in settings the box finds its place by name, with the Place ID
as the fallback; the rating and up to five reviews are refreshed daily and
cached within Google's terms; behind a port with a sandbox adapter.

## Decision
1. **Port** `Palee.ReviewAsks.Ports.Places`: `search(query, language:)` and
   `details(place_id, language:)`, answering normalised maps. Adapters:
   `GooglePlaces` (Places API (New): `places:searchText` and `places/<id>`
   with narrow field masks) and `SandboxPlaces` (dev, test).
2. **Key**: `GOOGLE_PLACES_API_KEY` → `config :palee, :google_places_api`.
   It travels only in the `X-Goog-Api-Key` header; never in a URL, log,
   response or export. Without a key the API answers `places_unavailable`
   and the settings keep the Place ID field.
3. **Snapshot** (`google_place_snapshots`, one row per box): place id, name,
   rating, rating count, Maps link, up to 5 reviews as Google returns them
   (author name, profile link and photo, stars, text, Google's relative time),
   `fetched_at`, `next_refresh_at`, status `ok | not_found | failed`.
   `GooglePlacesJob` runs hourly and refreshes boxes that are due (daily;
   failures back off 1 h → 24 h) through `palee_google_place_due_organizations`
   (SECURITY DEFINER, `search_path` only). Saving a new Place ID reads it at
   once.
4. **Shown**: only a snapshot of the current Place ID, younger than 7 days and
   with a rating. The app and site show it apart from Palee's reviews, with
   «Από το Google», each author's attribution and a link to the listing.
5. **Admin**: `GET /admin/review-asks/places?q=` (3–120 characters, the box's
   language), and the settings response carries the listing.

## Rationale
A daily snapshot keeps the Places bill to one Details call per box per day
(plus searches when setting up) and keeps pages fast. Place IDs may be
stored indefinitely under Google's terms.

## Alternatives Considered
- Calling Google on every page view: cost per visit and slower pages.
- Embedding Google's widget: third-party script on every page before consent.

## Consequences
- **Legal check needed**: Google Maps Platform terms allow storing Place IDs;
  other content is to be shown fresh. A 24-hour snapshot with attribution is
  the common practice but must be confirmed for Palee's contract (open
  question for ANR).
- Ops set `GOOGLE_PLACES_API_KEY` (restricted to the Places API (New), server
  IPs); cost is billed to Palee.
- Migration `20270511000000_box_reviews_and_site_v31.exs`.

## Amendment (v3.1 questions, 2026-11-03)

ANR, question 13: until a lawyer has checked Palee's use against Google's terms, the listing shows only the Google rating and the number of reviews, with «Από το Google» and the link to the listing, and no review texts. For data minimisation Palee also stops reading, storing and returning them: the Places field mask no longer asks for `reviews`, the port and snapshot carry none, the API's `GoogleListing` has no `reviews`, and migration `20270514010000` drops `google_place_snapshots.reviews` with the texts and author names already stored. Showing texts again needs the legal check and a new decision.
