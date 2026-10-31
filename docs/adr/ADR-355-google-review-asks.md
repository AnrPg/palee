# ADR-355: Google reviews from members, asked at a good moment, never gated or rewarded
Date: 2026-10-31
Status: Accepted

## Context
CP-C6 describes asking «πώς σου φαίνεται το box;» and sending only high
scores to Google while others write to the staff. That is **review gating**,
which Google's policy forbids ("Don't discourage or prohibit negative reviews
or selectively solicit positive reviews from customers"; "Don't offer or
accept money in exchange for reviews") and the EU Omnibus Directive treats as
a misleading practice. It also risks the box's listing.

## Decision
1. **New bounded context `Palee.ReviewAsks`**: `review_ask_settings` (Google
   Place ID, on/off, attendance milestones, default `[10, 50, 100]`),
   `review_asks` (one row per ask shown) and `review_ask_opt_outs`.
2. **Who is asked: a behavioural moment, never a score.** `ReviewAskPolicy`
   asks a member when every one of these holds, the same for everyone:
   asks are on and a Place ID is set; the member did not opt out; has an
   active membership and has been a member for at least 30 days; just reached
   an attendance milestone not asked before (at most 4 classes past it);
   attended within the last 2 days; is in the box's daytime (08:00–21:00 in its
   time zone); was not asked in the last 120 days; has been asked fewer than 3
   times in all. No question about satisfaction comes first.
3. **What is shown**: two equal options, «Γράψε κριτική στο Google» (opens
   `https://search.google.com/local/writereview?placeid=<id>`) and «Πες κάτι
   στο box» (the box inbox, ADR-282), plus «Αργότερα» and «Να μη ρωτηθώ ξανά».
   Every member gets the same choices: nobody is steered by their opinion.
4. **No incentive**: no XP, badge, discount or entry tied to the ask or the
   click; Palee cannot know whether a review was written and does not try.
5. **The moment**: the member app calls `GET /api/org/:slug/me/review-ask`
   when it opens after a class; the policy runs then and records the ask
   (`shown`). `POST /me/review-asks/:id/respond` records `opened`, `later` or
   `dismissed`; `PUT /me/review-asks/opt-out` stops asks for good (undo:
   `DELETE`). Signals come through the port `ReviewSignals` (attendance count
   and last attendance, membership, member since), whose adapter reads the
   box's tables under its RLS context.
6. **Staff** see settings and counts only (asked, opened, later, dismissed,
   opted out): `GET/PUT /admin/review-asks/settings`,
   `GET /admin/review-asks/summary`. No per-member list, so staff cannot chase
   who did not review.
7. **Personal data**: asks and opt-outs are in "Download my data" (ADR-267)
   and go with the member's profile (cascade on delete).

## Rationale
Selecting by engagement moment (right after a milestone class) asks people
when they are likely to have something to say, without filtering by opinion.

## Alternatives Considered
- The backlog's score-first flow: review gating, rejected for Google policy.
- An ask after every PR: too frequent; PRs can join the milestones later.

## Consequences
- CP-C6's text in the backlog needs ANR's agreement on the deviation.
- Migration `20270504100000_review_asks.exs`.
