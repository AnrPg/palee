# ADR-352: The box's website: sections from the box's own data, and a custom domain
Date: 2026-10-31
Status: Accepted

## Context
CP-C4 (`docs/plans/competitive-parity-and-beyond.md`): competitors sell a
done-for-you website (Kilo $175/month, Zen Planner $99/month). The public box
page (ADR-142, `/b/<slug>`) and the sales page (ADR-248, `/b/<slug>/packages`)
already render the published «Σχετικά», coaches, locations and the packages
sold online, with JSON-LD and link previews. What is missing is a site a box
can put on its own domain, whose sections follow the box's data without
anyone re-uploading changes, plus a timetable, FAQ and forms.

## Decision
1. **A new bounded context `Palee.BoxSite`** owns the site settings
   (`box_site_settings`, one row per box), its custom domains
   (`box_site_domains`), the form intake outbox (ADR-353) and the consent log
   (ADR-354). It never reads other contexts' tables; `Palee.Application.BoxSite.*`
   composes the public page (ADR-142), packages (ADR-248) and the schedule.
2. **Sections are keys, not content.** `SiteSections` lists
   `hero about schedule packages coaches location reviews faq trial_form contact_form`.
   The owner only orders them and switches them off; every section fills itself
   from data Palee already has (published snapshot, open locations, packages sold
   online, coaches on staff, the week's classes, the Google review link of
   ADR-355). A section with no data is hidden by the renderer, so the calm
   default is "everything on" and nothing needs setting up. The only content
   the site adds is up to 12 FAQ entries.
3. **The timetable stays an owner's choice.** Board 4 D2 (ADR-142 §8) keeps
   the class schedule behind sign-in on the box page. The site may show a
   timetable (class type, day, time, length; never spots, bookings or people)
   only when the owner turns on `public_schedule`; default off until ANR
   decides (open question).
4. **Public read** `GET /api/public/sites/:slug` returns the settings that are
   public (sections, FAQ, forms, the public tag ids of ADR-354, the Google
   review link) and, when allowed, the timetable of the next 7 days. The web
   composes it with `/api/public/boxes/:slug` and `/packages`, all three cached
   by Next (`revalidate`), so a site is static-ish HTML with JSON-LD
   (`ExerciseGym`, `Offer` per package, `Event` per class, `FAQPage`); no
   `aggregateRating` (Google ignores self-serving LocalBusiness reviews).
5. **Custom domain** (`box_site_domains`, up to 2 hosts per box, one primary):
   - The owner adds a host. Palee shows two DNS records: a TXT
     `_palee-challenge.<host>` = `palee-site-verification=<token>` (proves
     control) and a CNAME to `BOX_SITE_CNAME_TARGET` (default `sites.palee.app`)
     or, for an apex, A records to `BOX_SITE_A_RECORDS`.
   - States: `pending_dns` → `pending_tls` → `active`; an active host whose
     DNS stops pointing at us becomes `broken` (the site keeps working at
     `/b/<slug>`); `pending_dns` older than 14 days becomes `expired`.
   - Checks go through two ports: `DomainDns` (real adapter `:inet_res`, sandbox
     answers `*.test`/`*.example`) and `TlsProbe` (Req `GET https://<host>/api/public/sites/by-host/<host>`
     with `req_options` from config). `CheckSiteDomainsJob` rechecks due hosts
     (backoff 5 min → 24 h); «Έλεγχος τώρα» runs one check at once.
   - Hosts are unique across all boxes (unique index); public lookups go
     through `palee_site_by_host(text)` (SECURITY DEFINER, `search_path` only).
   - Palee hosts (`palee.app` and below), IPs, `localhost` and single-label
     names are refused.
6. **TLS through the existing ingress.** Production runs ingress-nginx with
   cert-manager `letsencrypt-production` HTTP-01 (handoff 2026-10-26 §0.5);
   self-hosting runs Caddy. Palee does not call the cluster API:
   - `GET /api/platform/site-domains?status=pending_tls` (vendors) lists hosts
     waiting for an Ingress; ops add one Ingress per host
     (see `docs/operations/box-site-custom-domains.md`).
   - `GET /api/public/sites/tls-allowed?domain=` answers 200 only for
     `pending_tls`/`active` hosts: Caddy's `on_demand_tls { ask }` endpoint,
     so a Caddy install issues certificates only for verified hosts.
   - When the probe passes the host becomes `active`.

## Rationale
Keys instead of a page builder keep CP-C4's "updates itself" promise and the
§4 calm-default principle: there is nothing to keep in sync. DNS TXT proof is
the industry pattern (Google, Shopify, Vercel) and keeps one box from claiming
another's domain. Leaving certificate issuance to the ingress keeps cluster
credentials out of the API.

## Alternatives Considered
- A free-form site builder (blocks, text, images): heavy, drifts from the real
  schedule and prices, and is what Kilo needs 157 help articles for.
- Issuing certificates from the API (ACME client, cert storage): duplicates
  cert-manager and needs secrets in the app.
- Reusing `organization_domains` (2026-07 app-tenant routing table): it is a
  platform table with user-based RLS and no verification state; kept as is.

## Consequences
- Ops add an Ingress per custom host until a controller automates it.
- The web needs a host → slug rewrite in middleware and the site routes once
  ANR approves the mockups (`v31-mockups/w4-web.html`).
- Sections and FAQ edits are live at once (no draft/publish): they hold no
  content of their own except the FAQ, and the profile keeps its own draft.

## Implementation Notes
- Migration `20270504000000_box_site.exs`.
- Admin: `GET/PUT /api/org/:slug/admin/site`, `GET/POST /admin/site/domains`,
  `POST /admin/site/domains/:id/check`, `PUT /admin/site/domains/:id/primary`,
  `DELETE /admin/site/domains/:id` (capability `manage_settings`).
