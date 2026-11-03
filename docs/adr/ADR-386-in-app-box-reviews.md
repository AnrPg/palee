# ADR-386: In-app reviews of a box, next to (not mixed with) Google's
Date: 2026-11-02
Status: Accepted

## Context
ANR's final W4 decision (UI-BUILD 2026-11-02, s6): the review request card on
Home offers three equal buttons, «Γράψε κριτική», «Γράψε και στο Google» and
«Πες κάτι στο box», and Palee gets its own reviews: stars plus text, in the
box's «Κριτικές» section in the app and on the website. Only people who
checked in may review, once each; the box replies but never deletes; Google
reviews stay separate with their own average. ADR-355 asked only for Google
reviews and needed a Place ID to ask at all.

## Decision
1. **Data** (`box_reviews`, tenant table in the ReviewAsks context): one row
   per person and box (`rating` 1–5, optional `body` up to 2,000 characters,
   `locale`, `edited_at`) and the box's reply (`reply_body`, `replied_at`,
   `replied_by_id`). Forced RLS and the tenant trigger.
2. **Who writes**: a person with at least one attended class at the box
   (`ReviewSignals.attendance_count > 0`, `review_needs_check_in` otherwise).
   A second write edits the first (`edited_at`).
3. **Nobody filters**: every review counts in the average and shows, newest
   first, whatever its stars. Staff can reply (and edit the reply) with the
   `message_from_box` capability (they speak as the box, as in the box inbox,
   ADR-282); there is no staff delete or hide. The author may delete their own
   review.
4. **Names**: the author shows by first name only (data minimisation); people
   who hide themselves in the community (ADR-143) show without a name.
5. **Where**: `GET /api/org/:slug/me/box-reviews` (list, average, mine,
   `can_review`, and the Google listing of ADR-387 apart),
   `PUT|DELETE /me/box-review`; staff `GET /admin/box-reviews`,
   `PUT /admin/box-reviews/:id/reply`; the website gets the count, average and
   the 6 latest (ADR-388).
6. **Asks (ADR-355 amended)**: an ask no longer needs a Place ID (the Google
   button shows only with one). An ask is shown once: it goes away after the
   visit that showed it and is never shown again (no 24 h re-show, no
   reminders, no push). Milestones stay 10, 50 and 100 attendances; no PR
   moment. The ask carries `has_review` so the card can say «Η κριτική σου».
7. **Personal data**: reviews are in "Download my data" (ADR-267, without
   `replied_by_id`) and go with the account (cascade on delete).

## Rationale
Reviews inside Palee are what a member can write without a Google account,
and they fill the website's «Κριτικές» section for boxes with no Google
listing. Keeping Google apart avoids mixing two audiences in one average and
keeps Google's own attribution rules intact.

## Alternatives Considered
- Letting staff hide reviews: is review gating after the fact (ADR-355).
- Showing full names: not needed to trust a review; first names suffice.
- JSON-LD `aggregateRating` from these reviews: Google ignores self-serving
  LocalBusiness reviews, so the website leaves it out (ADR-352 §4).

## Consequences
- Abuse (insults, personal data in a review) has no moderation path yet:
  open question for ANR (report to Palee, as for community posts?).
- Migration `20270511000000_box_reviews_and_site_v31.exs`.
