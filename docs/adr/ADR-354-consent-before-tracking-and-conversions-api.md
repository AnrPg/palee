# ADR-354: Meta Pixel, Google Analytics and Google Tag only after consent; consent log; Conversions API
Date: 2026-10-31
Status: Accepted

## Context
CP-C5: boxes want their own Meta Pixel / Google Analytics on their site.
ePrivacy art. 5(3) and GDPR need prior, freely given, specific consent for
non-essential cookies and similar tracking, as easy to refuse as to give
(EDPB guidelines 05/2020, cookie banner taskforce report 2023), and proof of
it (GDPR 7(1)).

## Decision
1. **Settings** (`box_site_settings`): `meta_pixel_id` (digits, 5–20),
   `ga4_measurement_id` (`G-XXXX`), `gtm_container_id` (`GTM-XXXX`). These are
   public ids and appear in the public site response. Off by default.
2. **Categories.** `necessary` (always; Palee sets no tracking cookie of its
   own), `analytics` (GA4), `marketing` (Meta Pixel, Google Ads tags). GTM
   loads only after analytics or marketing consent and gets Google Consent
   Mode v2 defaults `denied` for every signal, updated per category, so its
   tags follow the choice. Nothing third party loads before a choice ("basic"
   consent mode): no pre-consent pings.
3. **Banner model** (`ConsentPolicy`): first layer with «Αποδοχή όλων»,
   «Απόρριψη όλων» and «Ρυθμίσεις» of equal weight; no pre-ticked boxes; no
   banner at all when the box has no tags. A choice lasts 6 months, then the
   banner asks again. `banner_version` bumps whenever the box adds a tag, so
   consent is asked again for the new purpose. A footer link «Cookies» reopens
   the choice; withdrawing is one click.
4. **Consent log** (`box_site_consents`, insert-only): a pseudonymous
   `visitor_id` (random UUID in a first-party cookie, set only to remember the
   choice: strictly necessary), `banner_version`, `analytics`, `marketing`,
   `action` (`accept_all`, `reject_all`, `custom`, `withdraw`), `recorded_at`,
   `expires_at`. No IP, no user agent. Rows are deleted 2 years after they were
   recorded. `POST /api/public/sites/:slug/consents`.
5. **Conversions API (optional).** With `conversions_api_enabled` and an
   access token (encrypted with `EncryptedBinary`, write-only, never returned,
   logged or exported), a form submission whose `visitor_id` has an unexpired
   marketing consent queues a server-side `Lead` event with SHA-256 hashed,
   normalised email/phone, `event_id` = submission id (deduplicates with the
   browser pixel's `eventID`). Port `ConversionsApi` (Meta Graph adapter via
   Req, sandbox for dev/test); the event leaves through the same outbox, and
   the hashed payload is cleared once sent or failed.

## Rationale
Loading nothing before consent is the strictest reading and the simplest to
prove. Storing no IP or user agent keeps the log itself minimal.

## Alternatives Considered
- Google Consent Mode "advanced" (cookieless pings before consent): contested
  under ePrivacy in several EU authorities' guidance.
- A third-party CMP (Cookiebot, OneTrust): cost per box and another
  sub-processor for a three-category banner.

## Consequences
- The site's CSP must allow the tag hosts only on site routes, and only once
  consent is given (web, after the mockups).
- The box is the controller for its tags; Palee's privacy policy and the
  box's site notice must say so (open question for ANR's lawyer).
