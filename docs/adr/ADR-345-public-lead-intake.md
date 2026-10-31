# ADR-345: Public lead intake: spam protection, consent capture and retention of leads
Date: 2026-10-31
Status: Accepted (CP-C1; builds on ADR-142, ADR-267)

## Context
Leads arrive from the public box page form, join links and (W4) the box
web site. A public endpoint that stores personal data needs protection
from bots and must record a lawful basis (GDPR art. 6, 7) for contacting
the person, separately from any marketing.

## Decision
- `POST /api/public/boxes/:slug/leads` answers `202 {status: received}`.
  Only a published box page (ADR-142) takes enquiries.
- **Spam**: a rate limit of 5 per address per 10 minutes; a hidden
  honeypot field; a form submitted less than 3 s after it was shown
  (`form_started_at`); links in the name; more than two links in the
  message. Spam gets the same answer as a real enquiry, stores nothing,
  and is counted by telemetry. No CAPTCHA by default.
- **Consent**: inbound sources must carry `consent.contact = true`
  (answering this enquiry); `consent.marketing` is a separate, unticked
  choice. The version (and optional hash) of the text shown and the time
  are stored with the lead. Staff-entered leads imply contact consent
  only; marketing needs an explicit choice. Opting out of marketing is a
  lead action that also cancels queued automatic messages.
- **Same person again**: an enquiry with the email of an open lead joins
  it (`enquired_again`), never revealing to the sender whether the box
  knew them.
- **Minimisation and retention**: name, one contact, message ≤ 2,000
  characters; a lost lead without a Palee profile that did not move for
  two years is deleted by the daily job.

## Rationale
Honeypot + timing + rate limit stop the bulk of form spam with no friction
for people; a CAPTCHA adds a third-party processor and hurts conversion.
Equal answers for spam and real enquiries give bots no signal.

## Alternatives Considered
- hCaptcha / Turnstile: kept as a later option if spam passes the rules.
- Double opt-in email for every enquiry: too much friction for a
  "call me back" request; still the norm for marketing newsletters.

## Consequences
- The two-year purge is a default that may need to be a box setting.
- The web form must send `form_started_at`, the hidden field empty, and the
  consent text version it showed.

## Implementation Notes
- `Palee.Leads.Domain.IntakePolicy` (normalize, consent, spam_check).
- `Palee.Application.Leads.PublicIntake` and `CaptureLead`.
- Sources: GDPR art. 6(1)(a)/(b), art. 7; ICO guidance on consent and
  legitimate interests; OWASP Automated Threats to Web Applications (OAT-017 Spamming).
