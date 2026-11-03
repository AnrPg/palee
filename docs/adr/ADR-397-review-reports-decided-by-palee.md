# ADR-397: «Αναφορά» on box reviews, decided only by the Palee team
Date: 2026-11-03
Status: Accepted (backend and UI; the v3.2 questions decided on 2026-11-03, see below)

## Context
ADR-386 gave a box its own in-app reviews (stars and text by people who
checked in): the box replies but never deletes or hides one. It left one gap
open: abuse (insults, someone's personal data, a review that is not a real
experience) had no path at all. ANR's v3.1 questions (2026-11-03, item 14)
scheduled it for v3.2: «Αναφορά» for offensive text, checked by the Palee
team.

Palee stores the reviews and shows them to the box's members and, through
the box's website, to the public: for the EU Digital Services Act
(Regulation (EU) 2022/2065, "DSA") that is a hosting service (Art. 3(g)(iii))
and, because the reviews are disseminated to the public, an online platform
(Art. 3(i)). Hosting services must run a notice and action mechanism
(Art. 16) and give a statement of reasons to the person whose content they
restrict (Art. 17), whatever their size.

## Decision
1. **Who may report.** Any active member of the box who can read its reviews
   (`POST /api/org/:slug/me/box-reviews/:id/report`, role `member`), and the
   box itself: staff who already speak as the box when they reply
   (`message_from_box`, `POST /api/org/:slug/admin/box-reviews/:id/report`,
   role `box`). Nobody reports their own review
   (`cannot_report_own_review`). A hidden or removed review cannot be
   reported (it is not shown).
2. **Reasons.** A fixed list, stored as codes: `offensive` (insults, hate),
   `personal_data` (someone's personal data), `not_genuine` (not a real
   experience, or written for or against the box by an interested party),
   `spam` (ads or off-topic), `illegal` (other illegal content) and `other`.
   An optional note of up to 500 characters; required for `illegal` and
   `other`, where the code alone explains too little (Art. 16(2)(a)). The
   report keeps a copy of the review's stars and text at that moment, so an
   edit after the report cannot hide the evidence.
3. **A report changes nothing for anyone.** The review stays up and counted
   in the average until the Palee team decides. There is no automatic hiding
   after N reports. **The box can never hide a negative review on its own**,
   neither directly nor by asking friends to report it: only the Palee team
   hides or removes. This is what keeps the reviews trustworthy for members
   and for the website's visitors: a box that could hide what it dislikes
   would turn every average into marketing. It also keeps the box clear of
   the EU ban on misrepresenting consumer reviews (Unfair Commercial Practices
   Directive 2005/29/EC as amended by Directive (EU) 2019/2161, Art. 7(6) and
   Annex I point 23c).
4. **Duplicates and rate limits.** One open report per person and review
   (a second one answers 200 with the same open report). At most 10 reports
   per person and box in 24 hours (`review_report_limit`, 429), and a route
   cap of 10 POSTs an hour per person (`review_report_rate_limited`), on top
   of the tenant write budget.
5. **The Palee team's queue** (vendor console):
   `GET /api/platform/review-reports` lists one item per reported review,
   oldest first, across every box: the box, the author's first name (as the
   review shows), the review as reported and as it is now, the number of
   reports, the reasons with counts, the notes with the reporter's role
   (never who), and whether the box itself reported it (a conflict of
   interest the moderator weighs). `?status=decided` lists the latest 100
   decisions: who decided, when, outcome, ground and statement (the audit
   trail).
6. **Outcomes.** `POST /api/platform/review-reports/:review_id/decision`
   with `outcome`:
   - `keep`: no violation (`ground: no_violation`), the review stays;
   - `hide`: reversible; the text stays stored, nobody but the author sees it
     and it leaves the average and the website;
   - `remove`: the text and the box's reply are erased; the stars remain only
     as a tombstone the author sees, out of every list and the average.
   `hide` and `remove` need a `ground` (one of the report reasons) and a
   `statement` (1–1,000 characters) written for the author. One decision
   closes every open report on that review (`kept`/`hidden`/`removed`). A
   hidden or removed review cannot be edited by its author nor replied to by
   the box (`review_moderated`, 409); the author may still delete it.
   Without open reports there is nothing to decide (`review_report_decided`,
   409).
   - `restore` (`POST /api/platform/review-reports/:review_id/restore`, from
     «Αποφασισμένες»): shows a hidden review again, with a required
     `statement` for the author, who is notified. Only a hidden review can be
     restored (`review_not_hidden`, 409); a removed text is gone. Restore is a
     decision row of its own (`outcome: restore`, `ground: no_violation`), so
     the audit trail keeps both.
7. **Statement of reasons (DSA Art. 17).** The decision row
   (`box_review_decisions`) is the statement: the restriction (`hide` =
   visibility restricted, `remove` = removed), the ground and its basis
   (`law` for `illegal`, Palee's terms for the others: Art. 17(3)(d)/(e)),
   the facts in the moderator's words, that it was decided after a report
   (the reporter is never named: Art. 17(3)(b) allows it only where strictly
   necessary), that a person decided with no automated means (Art. 17(3)(c))
   and the redress available (`contact_palee` with Palee's moderation
   address in `contact`, and `court`: Art. 17(3)(f)). The
   author's `GET /me/box-reviews` returns it under `mine.moderation`, and a
   locked notification (`box_review_moderated`, category `account`) tells
   them the same day.
8. **The reporter hears the outcome** (DSA Art. 16(5)) through a locked
   notification (`box_review_report_decided`), whatever it is. The author is
   not notified of a `keep` (nothing changed for them, and telling them would
   only say that someone, possibly their box, complained; decided, question
   3).
9. **Audit trail.** Who reported and when (`box_review_reports.reporter_id`,
   `reporter_role`, `inserted_at`), who decided and when
   (`box_review_decisions.decided_by_id`, `decided_at`), and every decision in
   the vendors' audit log (`organization_provisioning_events`, event
   `box_review_moderated`, ADR-273).
10. **Data and RLS.** Both new tables are tenant tables with forced RLS and
    the tenant trigger; each also has a read-only policy for the Palee team
    (`palee_acting_user_is_vendor()`) so the queue spans every box. The
    decision is written in the box's own tenant session (the vendor's context
    with the box's `organization_id`, as the fiscal console does, ADR-273).
    `box_reviews` gains `moderation` (`hidden`|`removed`) and `moderated_at`;
    the box can never set them (the changeset does not cast them).
11. **Personal data.** "Download my data" (ADR-267) carries the person's own
    reports (reason, note, when, outcome; not whose review nor its text) and
    the decisions on their own reviews with the statement (not who decided).
    Account deletion: a deleted user row takes every report and decision of
    theirs by cascade; a profile kept anonymised (ADR-211) loses its reports
    through `palee_forget_box_review_reports(uuid)`. Deleting a review takes
    its reports with it; a decision outlives it with `review_id` cleared.

## Rationale
The Palee team, not the box, is the right moderator: the box is a party to
every review of itself. A fixed list of reasons keeps reports comparable and
the queue fast; the note covers the rest. Keeping the review up until a
person decides costs a few hours of an offensive text being visible, but
makes the report useless as a weapon against honest negative reviews.

DSA articles relied on: Art. 3(g)(iii) and (i) (hosting service, online
platform), Art. 6 (acting on actual knowledge), Art. 14 (terms must describe
the moderation; Palee's terms need a paragraph, see Consequences), Art. 16
(notice and action: electronic, substantiated, confirmation, decision sent to
the notifier, diligent and non-arbitrary handling, automated means
disclosed), Art. 17 (statement of reasons), Art. 18 (suspicions of crimes
against life or safety must be reported to the authorities; the moderator
does it by hand), Art. 19 (micro and small enterprises are exempt from
Section 3, Art. 20–28), Art. 20 (internal complaints, for when Palee is no
longer exempt), Art. 23 (misuse of notices).

## Alternatives Considered
- **Let the box hide reviews** (or hide them after its own report): is
  review gating after the fact, rejected by ADR-355 and ADR-386, and close to
  the UCPD ban on misrepresenting reviews.
- **Automatic hiding after N reports**: lets a box hide any review with a few
  friendly accounts.
- **Box staff moderate, as for club posts (ADR-143)**: a club is the box's
  own space; a review is about the box, so the box cannot be the judge.
- **Report as a free text only**: harder to triage and to report on.
- **`remove` deletes the row**: the author could post the same text again at
  once, and the statement would have no place to show next to it.
- **A non-tenant table for the queue**: would need a parallel security
  model; a vendor read policy on tenant tables is narrower and keeps every
  write in the box's session.

## Decisions of 2026-11-03 (v3.2)
ANR delegated the v3.2 choices; the coordinator decided the mockup's
questions as follows, and the UI was built with option A of all four parts.
1. **Who may report:** members and the box only; no public form on the
   website yet.
2. **Reasons:** the six above, unchanged.
3. **No notice to the author on `keep`.**
4. **Website footer:** a line «Αναφορά περιεχομένου: <address>» with a
   `mailto:` to Palee's moderation address (`site.report_contact`, from
   `config :palee, :review_moderation, contact_email`, env
   `REVIEW_MODERATION_EMAIL`). This is the electronic notice channel for
   visitors (Art. 16(1)); no form yet.
5. **Restore:** yes, from «Αποφασισμένες», with a statement; the author is
   notified (Decision 6).
6. **No appeal flow in v3.2.** The statement of reasons names the moderation
   address for redress and the courts. Palee is a micro or small enterprise,
   so Art. 20 does not apply yet (Art. 19); an internal complaint system is
   due when it no longer is.
7. **Retention:** a removed review's text (the report's copy and the
   reporter's note) is kept 6 months after the decision, then purged
   (`palee_purge_removed_review_texts(before)`, run daily by
   `Palee.Workers.ReviewReportsDailyJob` at 07:10). The decision row and its
   statement stay.
8. **Daily summary:** the same job emails the Palee team
   (`review_moderation.team_email`, env `REVIEW_MODERATION_TEAM_EMAIL`, in
   `team_locale`) when open reports exist: how many reviews, how many
   reports, the oldest. One email a day at most (idempotency key per day).
9. **No waiting period** between a report and a decision.
10. **Rate limit:** 10 reports per person and box per day, as in Decision 4.
11. **Terms of use:** the content moderation paragraph (DSA Art. 14: the
    reasons, that the Palee team decides, no automated decisions, the
    moderation address for redress) **needs the lawyer**, together with the
    website privacy template. Until it is checked, statements cite «όροι
    χρήσης Palee» as the basis for the non-illegal grounds.

## Consequences
- The UI (option A in all four parts of `v32-mockups/review-report.html`):
  «Αναφορά» in the ⋯ of every other review in Box › «Κριτικές», the report
  sheet (one sheet, reasons as a radio list, note under them), «Το ανέφερες»
  while open, the statement of reasons under «Η κριτική μου» (editing
  closed, «Διαγραφή» open), «Αναφορά ως box» in Settings › Reviews, and the
  console page `/platform/review-reports` (cards per review, «Ανοιχτές» and
  «Αποφασισμένες» with «Επαναφορά»).
- Palee's terms of use need the moderation paragraph, checked by a lawyer
  with the privacy template (decision 11).
- Migration `20270605000000_box_review_reports.exs`; notification types
  `box_review_moderated`, `box_review_report_decided` (category `account`,
  locked); email template `review_reports_summary`.

## Implementation Notes
- Domain: `Palee.ReviewAsks.Domain.ReviewReportPolicy` (pure); store
  callbacks on `ReviewAskStore`; application service
  `Palee.Application.ReviewAsks.ReviewReports`; controllers
  `MyBoxReviewsController.report`, `AdminBoxReviewsController.report`,
  `PlatformReviewReportController`.
- `GET /me/box-reviews` adds `reported_ids` (my open reports, so the app can
  show «Το ανέφερες») and `mine.moderation`.
- `list_reviews` and `review_stats` (app, staff and website) leave out
  moderated reviews.
- Daily job: `Palee.Application.ReviewAsks.ReviewReportsDaily.run/1`
  (purge, then the summary), cron `10 7 * * *`.
- Web: `components/reviews/ReviewReportSheet.tsx`, `ModerationNotice` in
  `ReviewParts.tsx`, `components/platform/PlatformReviewReportsPage.tsx`,
  `api/platform-review-reports.ts`; e2e `e2e/review-reports.spec.ts`.
