# ADR-462: Staff analytics filters, dimension snapshots, metric resets and the event mix
Date: 2026-11-04
Status: Accepted

## Context
«Στατιστικά» answered one question: what happened in the last `days` days, across the whole box. Owners asked for more:
- a chosen period with a comparison to the period before it;
- narrowing by branch, class, coach and package;
- a set of new KPIs;
- a way to start a figure again after a change (new schedule, new pricing) without deleting history.

Members asked for the same fresh start on their own «Πρόοδος» figures.

Filtering facts by class dimensions also exposed a problem. Joining live class rows gives the wrong answer once a class moves to another branch, changes coach or changes type. A fact must keep the dimensions it had when it happened.

## Decision
1. **One filter.** `Palee.Analytics.Domain.AnalyticsFilter` is a domain value object, and every staff summary takes it (`/admin/analytics/summary`, `/admin/finance/summary`).
   - Period: `from`/`to` are gym-local dates, both included, at most 731 days long. `days` (1–365, default 30) is kept for existing callers.
   - Every KPI is returned with `previous`, the value over the period of equal length that ends the day before `from`, plus `delta`.
   - Class dimensions: `location_ids` (always intersected with the staff member's branch scope), `class_type_ids`, `levels`, `coach_ids` and `time_of_day` (morning / midday / afternoon / evening by gym-local start hour).
   - People dimensions: `package_families`, `package_ids` and `tenure_bands` (`lt_3m`, `3_12m`, `gt_12m`).
   - Opt-in demographics only: `age_bands` and `genders`, plus an `unknown` option for each, taken from the leaderboard opt-in row (ADR-356). Palee still collects no date of birth (ADR-267).
   - Every query composes through one infrastructure module, `Palee.Infrastructure.Analytics.FilterQuery`.
2. **k-anonymity.** Any figure built from an age or gender selection, and any age or gender bucket (`unknown` included), that covers fewer than 5 people is returned as `suppressed: true` with no number. That includes the cohort size itself. Logic: `Palee.Analytics.Domain.KAnonymity`.
3. **Dimension snapshots.** Migration `20270712000000` adds snapshot columns to `analytics_events`, `class_attendance_records` and `attendance_records`:
   - `location_id`, `class_type_id`, `level`, `coach_user_id`, `package_family` and `dimensions` (jsonb);
   - `class_starts_at` on both attendance tables.

   The write paths fill these columns through `DimensionSnapshot` when they record a fact. The backfill is pure SQL and runs as the non-superuser migration role: it lifts FORCE RLS, runs UPDATE … FROM, then restores FORCE RLS. Every filter column has a partial index. Queries read `COALESCE(snapshot, live)`, so rows that could not be backfilled still count.
4. **Metric registry and staff resets.** `Palee.Analytics.Domain.MetricRegistry` lists every metric key, for both scopes, with its section, kind (`flow`, `snapshot`, `breakdown`) and unit. Keys are stable API.
   - A staff reset stores a baseline in `analytics_metric_resets` (scope `organization`). The metric's period then starts at the later of `from` and the baseline, and the previous period is cut or dropped to match. Nothing is deleted. An undo sets `undone_at`.
   - Snapshot metrics cannot be reset (422): a state has no start.
   - Only owners and admins can reset, through the new `reset_analytics` capability, which no box can grant to another role.
   - Each reset and each undo is recorded as an analytics event (`analytics_metric_reset`, `analytics_metric_reset_undone`), which is the audit trail.
   - Endpoints:
     - `POST /admin/analytics/metrics/:metric_key/reset` returns 201.
     - `POST /admin/analytics/resets/:id/undo` returns 409 if the reset was already undone.
     - `GET /admin/analytics/resets` returns the history, paginated, with each metric's value over the `days` before the reset.
5. **Member resets.** Scope `member` rows belong to the user and have no organization. Row-level security lets only that user see them. The endpoints are:
   - `POST /me/progress/metrics/:metric_key/reset`
   - `POST /me/progress/resets/:id/undo`
   - `GET /me/progress/resets`

   `/me/progress` and `/me/progress/depth` apply the member's active baselines and return them as `metric_baselines`. Box analytics, leaderboards and the coach view never read member-scope rows. A member reset emits no box event.
6. **«Κατανομή γεγονότων».** Every event in `EventCatalog` belongs to a category: classes, trials, wod, training, notifications, payments, referrals, messages, shop, perks, health, feedback, analytics, or `other` as the fallback. The summary returns `events.by_category`: `[%{category, total, events: [%{name, count}]}]`. The web labels every category and event from the `AnalyticsEvents` namespace in all 12 locales.

## Rationale
- A single filter object and a single composition module keep every metric consistent. Without them, each KPI would grow its own slightly different reading of "branch" or "period".
- Snapshots on the fact rows are the only way history stays true after a class is edited. Keeping the live join as the COALESCE fallback avoids a cliff for old rows.
- A baseline instead of a delete keeps resets reversible and auditable. It also leaves the raw facts for exports and the platform console.
- k-anonymity at 5 keeps the opt-in demographics useful without letting a small box single out a person.

## Alternatives Considered
- **Separate dimension tables or a star schema.** More work, and a second write path to keep in sync. The facts are small enough to carry their own columns.
- **Resetting by deleting or archiving facts.** Not reversible, and it would break finance and the audit trail.
- **Collecting age and gender in a new staff-visible field.** Rejected: ADR-267 and ADR-356 keep demographics opt-in and member-owned.
- **One shared reset for staff and member.** Rejected: a member's fresh start must never change what the box sees.

## Consequences
- Some KPIs cannot be computed reliably from what box staff may read. They are left out of the registry:
  - `training.prs_set`: PR records are hidden from box staff by RLS.
  - Per-type notification open rate: `notifications` is owner-only, and read/click events are account-level with no organization.
- Some figures are approximations:
  - `finance.ltv` is an estimate: ARPM ÷ monthly churn, null when churn is 0.
  - `finance.days_sales_outstanding` is the average number of days from issue to last payment, over invoices fully paid in the period.
  - Tenure uses `organization_memberships.joined_at` where staff may read it, otherwise the first membership start.
- The legacy feedback and wellbeing blocks still use `days`.
- The tenancy audit gains a `ready_mixed` class for `analytics_metric_resets`, a table with both organization rows and user rows.

## Implementation Notes
- Domain: `AnalyticsFilter`, `KAnonymity`, `MetricRegistry`, `MetricBaseline`, plus the `KpiReport` query.
- Ports: `KpiStore` and `MetricResetStore`, with Ecto adapters under `Palee.Infrastructure.Analytics`.
- Application: `ResetAnalyticsMetric`, `UndoAnalyticsMetricReset`, `ListAnalyticsMetricResets`.
- Errors: `unknown_metric` 404, `metric_not_resettable` 422, `already_undone` 409 (FallbackController).
- OpenAPI schemas live in `PaleeWeb.Schemas.AnalyticsMetrics`.
- The web shows the reset control in each widget's «?» infobox footer. No new button.
