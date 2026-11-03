# ADR-366: Status incidents in any language, the status screens and the in-app strip
Date: 2026-11-02
Status: Accepted

## Context
ADR-364 built the status page backend (probes, incidents, subscribers). The
product owner (ANR) then approved the screens (`v31-mockups/board/w7-trust.html`,
screens 1 and 2) with these decisions:

- Any Palee team member (vendor) may publish, and the publisher is shown.
- The incident's title and text are written in ANY language. Palee makes an
  English translation through the existing Gemini adapter; the console shows
  it as an editable preview marked «αυτόματη μετάφραση». When translation
  fails, the incident is published untranslated.
- The public page lives at `status.palee.app` (and `/status` as a fallback
  route), in the public «Σχετικά» layout: 30 days per component on a phone,
  90 on a desktop, the current incident with its latest update, past
  incidents and the email sign-up.
- An in-app strip is shown only during an active incident, only to people who
  use the affected component (members too), with no close button; it goes
  away when the incident is resolved.

## Decision
1. **Translation port.** `Palee.Status.Ports.Translator.to_english/2` with
   `GeminiTranslator` (platform `GEMINI_API_KEY`, `GEMINI_TRANSLATE_MODEL`,
   default `gemini-2.5-flash-lite`, JSON answer, metered as
   `status_translation`) and `SandboxTranslator` (dev and test). Only the
   text the Palee team wrote is sent.
2. **Preview endpoint.** `POST /api/platform/status/translations` (vendors)
   answers `{locale, title, body}`: the detected source language and the
   English text, or `503 status_translation_unavailable`.
3. **Storage** (`20270513000000`): `status_incidents.locale`, `title_en`,
   `en_source`; `status_incident_updates.locale`, `body_en`, `en_source`
   (`auto` | `edited`). English text carries no copy. The incident and step
   bodies accept these fields (`Domain.Translation.from_params/2`, error
   `invalid_status_translation`).
4. **Readers.** Status emails and the web show the original to readers whose
   language is the source language and the English copy to everyone else
   (`Translation.for_reader/3`); a machine translation is labelled as such.
5. **Publisher.** The console's incidents carry `published_by` (the
   publisher's display name) on the incident and on every step. Public
   responses never carry it.
6. **Web.** `/status` (public, no app chrome; `proxy.ts` rewrites `/` on the
   status host, `STATUS_HOST`, default `status.palee.app`), the console
   `/platform/status` (styled like «Ειδοποιήσεις συσκευών»), and the strip in
   the root layout.
7. **Who sees the strip** (`lib/service-status.ts`): `app`, `search`,
   `files` and `email` concern every signed-in person; `payments` concerns
   everyone with a box membership (members pay, staff take payments);
   `fiscal` concerns staff of a box (owner, admin, manager, front desk). The
   strip shows active incidents and maintenance in progress whose impact is
   not `none`, refreshes every minute and has no close button.

## Rationale
- A preview before publishing keeps a person responsible for the public text
  while letting the team write in their own language.
- Storing the source language lets each reader see the original when they
  can read it, instead of a translation of a translation.
- Mapping components to audiences in the web keeps the strip quiet for
  people who are not affected, without a new API.

## Alternatives Considered
- **Translate on publish, without preview.** Rejected by ANR: the publisher
  must be able to correct the English.
- **Translate into all 12 app languages.** More model calls and more text to
  check for each incident; English is the agreed common language.
- **A dismissible strip.** Rejected by ANR: it must stay until resolved.

## Consequences
- One model call per preview; failures are visible in the console and never
  block publishing.
- The strip polls the public, cacheable status endpoint once a minute per
  open app.

## Implementation Notes
- `Palee.Status.Domain.Translation`, `Ports.Translator`,
  `Infrastructure.Status.{GeminiTranslator, SandboxTranslator}`,
  `PlatformServiceStatus.translate/2`, `PlatformStatusController.translate`.
- Web: `components/status/*`, `components/platform/PlatformStatusPage.tsx`,
  `lib/service-status.ts`, `api/service-status.ts`.

## Amendment (v3.1 questions, 2026-11-03)

ANR, question 6: a planned maintenance enters the in-app strip only in the 24 hours before its `scheduled_for` (and while it runs); earlier it shows only on the status page. The strip reads the overview's `upcoming` list against an injected clock (`stripIncident(active, viewer, {upcoming, now})`, `maintenanceDueSoon`), keeps active incidents and maintenance first, and says when a maintenance starts («Ξεκινά …»). No API change.
