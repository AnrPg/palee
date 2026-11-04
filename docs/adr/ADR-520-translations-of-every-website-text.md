# ADR-520: Translations of every website text
Date: 2026-11-04
Status: Accepted (supersedes the English-only fields of ADR-388)

## Context
ADR-388 gave the box website one extra language: an `about_en` column and
`question_en` / `answer_en` keys inside each FAQ entry, typed into free-text
boxes under «Για προχωρημένους». ANR called it the worst UX: the owner could
not see what was missing, could not translate packages, class types, events,
rooms or locations at all, could not add any language other than English, and
had no way to know when the Greek text changed and the English one became
wrong. ANR picked alternative A of the mockup board
(https://claude.ai/artifact/… comment "this", 2026-11-04) and asked for it to
be built "robustly across all layers of hexagonal architecture".

## Decision
1. **A generic bounded context `Palee.ContentTranslations`.** One table,
   `content_translations` (tenant RLS, FORCE), keyed by
   `(organization_id, locale, subject_kind, subject_id, field)`, holding the
   text, the sha256 of the source it was made from, its origin
   (`manual` / `machine`) and `reviewed_at`. The context never reads the
   sources: callers hand it `%{key: {kind, id, field}, text}`. The catalog
   `Domain.Subjects` lists what can be translated and the maximum lengths:
   `box_profile.about`, `site_faq.question|answer`, `package.name|description`,
   `class_type.name`, `event.title`, `space.name|description`, `location.name`.
   A new translatable text is one catalog line plus one source in the
   application layer.
2. **Status by hash, never by timestamps.** `missing` (no row), `stale`
   (row made from a different source), `machine` (machine text nobody checked),
   `ok`. A check constraint forces `reviewed_at` on every manual row.
3. **Languages per website.** `box_site_settings.translation_locales`
   (being translated) and `visible_locales` (shown to visitors, ⊆ translated),
   from the app's 12 locales minus the box's own language. A new language
   starts hidden; untranslated texts fall back to the box's language.
4. **Machine translation through a port.** `Ports.MachineTranslator`
   (Gemini with the platform key, metered as `site_translation`; a sandbox
   adapter in dev/test). It only fills `missing` and `stale` texts, never
   replaces a person's current text, and its output is visible straight away
   but marked «Αυτόματη · έλεγξέ τη» until the owner keeps it.
5. **Composition in `Palee.Application.BoxSite.SiteTranslations`.** It
   gathers the sources of the sections the owner shows (about and rooms,
   FAQ, packages sold online, class types when the timetable or coaches show,
   upcoming events, locations) and serves the admin endpoints
   `GET/PUT /admin/site/translations`, `POST …/keep`, `POST …/machine` (503
   when the translator is unavailable).
6. **Public site.** `/b/<slug>/<code>` for every visible language (static
   app routes such as `/me` and `/tv` still win), `?lang=` on the public site
   read; the API resolves the texts it serves itself (about, FAQ, events,
   timetable) and returns `texts` / `class_type_names` for the rest. hreflang
   alternates list every visible language; the first visit follows the
   browser's language when the box shows it.
7. **UI (alternative A).** Settings › Website gets «Γλώσσες ιστοσελίδας»
   (progress bar, show switch, «Μετάφραση», remove in «⋯»). The new page
   «Μεταφράσεις» puts the box's text and its translation side by side, grouped
   in the website's order, filtered by «Θέλουν κάτι / Λείπουν / Άλλαξαν /
   Αυτόματες / Όλα», saving each field on blur, with «Εντάξει, κράτα το»,
   «Αυτόματη μετάφραση (N)» and «Ένα-ένα» (Enter saves, Esc skips).

## Rationale
Side-by-side lists with status filters, hash-based "source changed" flags and
"fill missing with machine translation, then review" are what translation
tools (Crowdin, Lokalise, Weglot, Shopify Translate & Adapt) converge on.
A generic context keeps each owning context free of per-language columns and
lets future texts (shop products, perks, programs) join without migrations.

## Alternatives Considered
- **Per-language columns on each table** (the ADR-388 approach): a migration
  per language and per text, no staleness, no machine fill.
- **JSONB `translations` map on each owning row**: no shared status,
  progress or machine flow; each context would re-implement them.
- **B: translate inside each editor** and **C: one-by-one only**: B scatters
  the work over seven screens; C became a mode inside A.

## Consequences
- `about_en` and the FAQ `_en` keys are migrated into rows and dropped
  (reversible migrations `20270901000000`, `20270901000100`). FAQ entries now
  carry a stable uuid `id`.
- The box name, coach names, reviews and the WOD of the day are not
  translated (said on the page).
- Deleting a source leaves its translation row behind until the box is
  purged; rows are invisible because they never match a source.

## Implementation Notes
- `TranslationPolicy.locales/0` is pinned to `Identity.Domain.Locale.supported/0`
  by a test.
- The store is listed in `mix palee.architecture` as tenant-scoped and
  ContentTranslations is registered in `TenantDataContexts` (export/purge).
- ADR-500 was first used on this branch and renamed to ADR-520 because
  another branch already holds ADR-500 and ADR-510.
