# ADR-364: Public status page, incidents and uptime history
Date: 2026-10-31
Status: Accepted

## Context
CP-G4 (competitive-parity backlog): the big competitors have a status page,
and Wodify's reviews complain about outages nobody announced. Palee already
has readiness checks (`/api/health`, ADR-043/116), Prometheus alerts and a
Grafana board (ADR-116), but all of it is internal: a box owner whose
members cannot book has no place to see whether Palee knows. Owners of
small boxes also asked "what happens when it is down?" during pilots.

Constraints: no new dependencies; ports and adapters (ADR-043); no PII in
public data; email goes through the outbox with its daily budget (ADR-203);
the page must be able to move outside the cluster later, because a page
served by the same cluster dies with it.

## Decision
1. A platform-level bounded context `Palee.Status` (no tenant data).
   Components shown publicly: `app` (database, Redis, Oban together),
   `search`, `files`, `email`, `payments`, `fiscal`.
2. **Probes.** `Palee.Status.Ports.DependencyProbe` checks every component
   once a minute (`StatusProbeJob`, Oban cron). `LiveProbe` reuses the
   readiness checks for app/search/files, reads the email outbox
   (`degraded` while mail is deferred past the daily budget, `down` once the
   SMTP key has expired) and reaches the providers' APIs for payments
   (Stripe, Viva) and fiscal (myDATA) from `:status_probe_targets` without
   credentials (any HTTP answer below 500 = reachable). `SandboxProbe` is
   used in test; dev has no external targets.
3. **Storage** (`20270507000000_create_service_status`):
   `status_component_states` (latest per component, `changed_at` moves on a
   change only), `status_daily_samples` (per component and UTC day: total,
   operational, degraded, down; kept 90 days), `status_incidents` and
   `status_incident_updates` (timeline), `status_subscribers`. Public tables
   are readable by anyone under RLS; writes need a vendor or a system session.
   Subscribers are never readable by a signed-in non-vendor.
4. **What the page says** (`Overview`, pure): a component is `maintenance`
   during an active maintenance that names it, else the worse of its probe
   and the active incidents naming it (minor → degraded, major/critical →
   down); a probe older than 5 minutes is `unknown`, never "all good".
   Overall: `major_outage` (critical incident or app down), `partial_outage`,
   `degraded`, `maintenance`, `unknown`, `operational`.
5. **Incidents and maintenance** are written by the Palee team in the
   platform console: `POST /api/platform/status/incidents`,
   `POST .../incidents/:id/updates` (each step has a note; resolved/completed
   closes it), `PATCH .../incidents/:id` (correct title, impact, components
   without a note or email), `GET /api/platform/status` (probes *with* their
   internal reasons, 90 days of incidents, subscriber counts).
6. **Public data API**, no session, `cache-control: public, max-age=30`:
   `GET /api/public/status` (now) and `GET /api/public/status/history?days=1..90`
   (uptime per component and day, incidents in the window). Probe reasons
   are never public.
7. **Status emails**, double opt-in: `POST /api/public/status/subscriptions`
   (always `202 accepted` for a valid address, no enumeration; a one-time
   token by email), `.../confirm`, `.../unsubscribe` (a signed token over the
   subscriber id; deletes the row). Only the address, its digest, language and
   confirmation time are stored; sign-ups never confirmed are deleted after
   48 hours by the daily sweep. A step with `notify` queues `StatusNotifyJob`,
   which sends `:status_update` through the outbox in batches of 100 with an
   idempotency key per update and subscriber. Emails are in 12 languages
   (gettext domain `status`).

## Hosting outside the cluster (documented option)
The page is designed so it can leave the cluster without code changes:
- **Data.** The two public reads need no session and are cacheable; any
  static host can render them. `config :palee, :status_page_url` moves the
  links in emails to that host.
- **Recommended setup when we move it:** (a) an independent uptime monitor
  outside our provider (e.g. a free GitHub Actions/Upptime workflow or a
  hosted checker) probes `https://<host>/api/health` and the public status
  endpoint every few minutes, so a total outage of the cluster still shows;
  (b) the static page reads `/api/public/status` with a short timeout and,
  when it cannot, shows the external monitor's state and "Palee is not
  answering"; (c) the API then needs CORS for that one origin on
  `/api/public/status*` (not added now: the page is served by our own web
  app first).
- **Alerts** stay in Alertmanager (ADR-116); the status page is the public
  face, not the alerting path.

## Rationale
- Reusing readiness checks and the outbox keeps the feature dependency-free
  and consistent with `/api/health`.
- Daily counters instead of raw samples: 6 components × 90 days = 540 rows,
  and the history query is trivial.
- Incidents are written by people: automatic public incidents from probes
  would announce every blip; the probe state is shown live anyway.
- Showing `unknown` when probes are stale prevents the classic "all green
  while everything is down" status page.

## Alternatives Considered
- **A hosted status page product (Statuspage, Instatus).** Monthly cost and
  another vendor with subscriber emails; rejected for now, kept as the
  "outside" option if ANR prefers it.
- **Prometheus/Alertmanager as the source of the public page.** Optional
  Compose profile (may not run), and alert rules are not a public contract.
- **Store raw probe samples.** 260k rows per 90 days for no extra value.
- **Unsubscribe tokens stored in the table.** A signed token over the id
  needs no storage and stops working once the row is gone.

## Consequences
- One cron job a minute runs the readiness checks plus up to three outbound
  HTTPS calls (3 s timeout each, in parallel).
- Status emails share the outbox's daily budget (280 non-security emails a
  day on the current provider plan). A large subscriber list on a bad day
  is deferred to the next day. Before the list grows past ~200 we need a
  bigger plan or a separate sender (open question for ANR).
- `status_subscribers` is not linked to accounts (it may hold any address):
  the unsubscribe link erases it, and a person's "Download my data" does not
  include it. An account deletion does not remove a status subscription made
  with the same address.
- The screens (public page, console panel) wait for ANR's choice among the
  mockups (`v31-mockups/w7-trust.html`).

## Implementation Notes
- Context `Palee.Status` (domain: `Components`, `IncidentPolicy`,
  `Overview`, `Uptime`, `SubscriberPolicy`; ports: `StatusStore`,
  `DependencyProbe`, `Clock`); adapters `EctoStatusStore`, `LiveProbe`,
  `SandboxProbe`, `SystemClock`; application services
  `PublicServiceStatus`, `PlatformServiceStatus`, `ServiceStatusJobs`,
  `ServiceStatusLinks`; workers `StatusProbeJob`, `StatusNotifyJob`.
- Tables are listed as platform-administered in the tenancy audit.
- Rate limit `public-status` (10 a minute per client) on the subscription
  endpoints; reads use the public box bucket.
- Telemetry `[:palee, :status, :probe]` per component and status.
