# ADR-362: Help centre: articles in 12 languages, searchable, linked from screens
Date: 2026-10-31
Status: Accepted

## Context
CP-G2: people need answers inside the app, in their language, and the support assistant (ADR-363)
needs a trusted source. Palee has in-app guides (ADR-193) and a feature catalogue, but no articles.

## Decision
1. **Articles** `help_articles` (platform table, not tenant): one row per `slug` + `locale` (12
   locales), title, summary, body (Markdown-like text, HTML refused), audience (`staff`, `member`,
   `all`), feature key, guide id (opens an ADR-193 guide), screens (app paths, `:param` and `[param]`
   segments match anything), keywords, position, status (`draft`/`published`), source
   (`seed`/`team`), version, `complete` (false while a translation is only the summary).
   Row policy: anyone reads published rows; only the Palee team (vendor) or the system writes.
2. **Seed** `priv/help_centre/articles.json`, built by `npm run help:seed` (apps/web) from the feature
   catalogue and the guides' messages: 19 articles × 12 locales. Seeding never overwrites the team's
   edits (only older `seed` versions). `mix palee.help_centre.seed` and `Palee.Release.seed_help_centre/0`.
3. **Search** port `ArticleSearchIndex`: Meilisearch adapter (index `MEILI_HELP_INDEX`, filter by
   locale/audience/feature, typo tolerance) and a database adapter (used in tests and dev, and as the
   fallback whenever the index is down) ranking accent-insensitively with a boost for the reader's
   screen. Results come in the reader's locale, else English with `fallback: true`.
4. **Public API** (no sign-in, rate limited): `GET /public/help/articles` (q, locale, audience, screen,
   feature, limit), `GET /public/help/articles/{slug}`, `GET /public/help/screen?path=` (a screen's «?»).
5. **Console** (vendors): `GET /platform/help/articles`, `PUT /platform/help/articles/{slug}/{locale}`,
   `DELETE …`, `POST /platform/help/reindex`.

## Rationale
Articles in the database let the Palee team fix answers without a release; the seed gives every
language a start. Meilisearch is already in the stack; the database fallback keeps help working.

## Alternatives Considered
- A hosted help desk (Zendesk, Intercom): another processor, no app-path links, no 12-language seed.
- Articles as static files in the web app: no edits without deploys, no search across languages.

## Consequences
- Non-en/el articles start as summaries (`complete: false`) until translated.
- Screens add a «?» that calls `/public/help/screen` (to be built in the web workstream).

## Implementation Notes
- `lib/palee/help_centre/**`, `lib/palee/application/help_centre/**`,
  migration `20270506000000_create_help_articles.exs`.
