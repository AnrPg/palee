"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";

import { fetchStaffAnalyticsSummary } from "@/api/analytics";
import { BranchSplits, type BranchSplit } from "@/components/admin/BranchFilter";
import { ExecutionKpiDashboard } from "@/components/admin/ExecutionKpiDashboard";
import { AnalyticsFilterBar } from "@/components/admin/analytics/AnalyticsFilterBar";
import { KpiSections, PlainTile, WidgetCard } from "@/components/admin/analytics/KpiWidgets";
import { useAnalyticsDirectory } from "@/components/admin/analytics/use-analytics-directory";
import { useAnalyticsFilter } from "@/components/admin/analytics/use-analytics-filter";
import { PageHeader, pageHeaderActionClass } from "@/components/PageHeader";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { BackLink } from "@/components/ui/BackLink";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import type { AnalyticsDimension } from "@/lib/analytics-filter";
import { readKpi } from "@/lib/analytics-kpi";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : {};
}

function metricNumber(record: Record<string, unknown>, key: string) {
  const value = record[key];
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function metricText(record: Record<string, unknown>, key: string) {
  const value = record[key];
  return typeof value === "string" && value.length > 0 ? value : "unknown";
}

function formatCount(uiLocale: string, value: number) {
  return new Intl.NumberFormat(uiLocale).format(value);
}

function formatMoney(uiLocale: string, cents: number) {
  return new Intl.NumberFormat(uiLocale, {
    style: "currency",
    currency: "EUR",
    maximumFractionDigits: 0,
  }).format(cents / 100);
}

function entries(record: Record<string, unknown>) {
  return Object.entries(record)
    .filter(([, value]) => typeof value === "number" && Number.isFinite(value))
    .sort((left, right) => Number(right[1]) - Number(left[1]));
}

function BreakdownList({ title, rows, helpPath }: { title: string; rows: [string, unknown][]; helpPath: string }) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const numericRows = rows.filter(([, value]) => typeof value === "number") as [string, number][];
  const max = Math.max(...numericRows.map(([, value]) => value), 1);

  return (
    <WidgetCard label={title} helpPath={helpPath}>
      {numericRows.length > 0 ? (
        <div className="space-y-4">
          {numericRows.map(([label, value]) => (
            <div key={label}>
              <div className="flex min-w-0 items-center justify-between gap-3 text-sm">
                <span className="min-w-0 truncate capitalize text-[var(--text-soft)]"><SemanticLabel value={label} /></span>
                <span className="shrink-0 font-bold text-[var(--text)]">{formatCount(uiLocale, value)}</span>
              </div>
              <div className="mt-2 h-2 rounded-full bg-[var(--panel-muted)]">
                <div
                  className="h-2 rounded-full bg-[var(--success)]"
                  style={{ width: (Math.max((value / max) * 100, value > 0 ? 8 : 0)) + "%" }}
                />
              </div>
            </div>
          ))}
        </div>
      ) : (
        <p className="text-sm text-[var(--muted)]">{i18n("noCapturedFactsInThisReportingWindowdc344c7")}</p>
      )}
    </WidgetCard>
  );
}

type EventMixGroup = { category: string; total: number; events: { name: string; count: number }[] };

function eventMixGroups(value: unknown): EventMixGroup[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const group = asRecord(item);
    if (typeof group.category !== "string" || typeof group.total !== "number") return [];
    const events = (Array.isArray(group.events) ? group.events : []).flatMap((event) => {
      const row = asRecord(event);
      return typeof row.name === "string" && typeof row.count === "number" ? [{ name: row.name, count: row.count }] : [];
    });
    return [{ category: group.category, total: group.total, events }];
  });
}

// ADR-462 §6: the event mix grouped by category, with translated labels.
// Its figure is the metric `engagement.event_mix` (own infobox and reset).
function EventMixList({ groups, since }: { groups: EventMixGroup[]; since: string | null }) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const t = useTranslations("AnalyticsEvents");
  const staffT = useTranslations("StaffAnalytics");
  const max = Math.max(...groups.map((group) => group.total), 1);
  const label = (key: string, raw: string) => (t.has(key) ? t(key) : <SemanticLabel value={raw} />);

  return (
    <WidgetCard
      label={staffT("metrics.engagement.event_mix.label")}
      since={since}
      helpPath="metrics.engagement.event_mix"
      metricKey="engagement.event_mix"
      testId="kpi-engagement.event_mix"
    >
      {groups.length > 0 ? (
        <div className="space-y-5">
          {groups.map((group) => (
            <div key={group.category}>
              <div className="flex min-w-0 items-center justify-between gap-3 text-sm">
                <span className="min-w-0 truncate font-bold text-[var(--text)]">{label(`categories.${group.category}`, group.category)}</span>
                <span className="shrink-0 font-bold text-[var(--text)]">{formatCount(uiLocale, group.total)}</span>
              </div>
              <div className="mt-2 h-2 rounded-full bg-[var(--panel-muted)]">
                <div
                  className="h-2 rounded-full bg-[var(--success)]"
                  style={{ width: (Math.max((group.total / max) * 100, group.total > 0 ? 8 : 0)) + "%" }}
                />
              </div>
              <ul className="mt-2 space-y-1">
                {group.events.map((event) => (
                  <li key={event.name} className="flex min-w-0 items-center justify-between gap-3 text-xs text-[var(--text-soft)]">
                    <span className="min-w-0 truncate">{label(`events.${event.name}`, event.name)}</span>
                    <span className="shrink-0">{formatCount(uiLocale, event.count)}</span>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      ) : (
        <p className="text-sm text-[var(--muted)]">{i18n("noCapturedFactsInThisReportingWindowdc344c7")}</p>
      )}
    </WidgetCard>
  );
}

export type AnalyticsSection = "overview" | "training" | "coaching" | "engagement" | "health";

/** The filter groups that narrow each page's figures (ADR-462 §1). */
export const SECTION_DIMENSIONS: Record<AnalyticsSection, readonly AnalyticsDimension[]> = {
  overview: ["location_ids", "package_ids", "tenure_bands", "age_bands", "genders"],
  training: ["location_ids", "class_type_ids", "levels", "coach_ids", "time_of_day", "package_ids", "tenure_bands", "age_bands", "genders"],
  coaching: ["location_ids", "class_type_ids", "levels", "coach_ids", "time_of_day", "age_bands", "genders"],
  engagement: ["location_ids", "package_ids", "tenure_bands", "age_bands", "genders"],
  health: ["location_ids", "class_type_ids", "levels", "coach_ids", "time_of_day", "age_bands", "genders"],
};

/** The metric keys each page shows; the overview also has the opt-in demographics. */
const SECTION_PREFIXES: Record<AnalyticsSection, readonly string[]> = {
  overview: ["overview.", "demographics."],
  training: ["training."],
  coaching: ["coaching."],
  engagement: ["engagement."],
  health: ["health."],
};

/** Keys a page draws in a widget of its own. */
const OWN_WIDGET = ["training.execution_kpis", "engagement.event_mix"];

export function AdminAnalytics({ section = "overview" }: { section?: AnalyticsSection }) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const t = useTranslations("StaffAnalytics");
  const branchT = useTranslations("BranchScope");
  const SECTION_TITLE: Record<AnalyticsSection, string> = {
    overview: i18n("overview0efc2e6"),
    training: i18n("trainingPerformancea32baa9"),
    coaching: i18n("athleteActivityAndFollowUp5a9fe9c"),
    engagement: i18n("interactionSignalsff55586"),
    health: i18n("injuryAndLimitationSignalsfc3b586"),
  };
  const { tokens } = useSession();
  const organizationSlug = useOrganizationSlug();
  const directory = useAnalyticsDirectory();

  // ADR-462: one period and one filter for the whole page, kept in the URL.
  const analyticsFilter = useAnalyticsFilter();

  const summaryQuery = useQuery({
    queryKey: ["admin", "analytics", "summary", analyticsFilter.queryKey],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => fetchStaffAnalyticsSummary(tokens!.access_token, analyticsFilter.apiQuery),
  });

  const payload = asRecord(summaryQuery.data);
  const analytics = asRecord(payload.analytics);
  const events = asRecord(analytics.events);
  const teamWorkouts = asRecord(analytics.team_workouts);
  const teamWorkoutsAggregate = asRecord(teamWorkouts.aggregate);
  const teamWorkoutsByUser = asRecord(teamWorkouts.by_user);
  const feedback = asRecord(payload.feedback);
  const wellbeing = asRecord(payload.wellbeing);
  const finance = asRecord(payload.finance);
  const coaching = asRecord(payload.coaching);
  const dashboard = asRecord(payload.dashboard);
  const crossContext = asRecord(dashboard.cross_context);
  const dashboardFinance = asRecord(dashboard.finance);
  const dashboardCoaching = asRecord(dashboard.coaching);
  const financeTotals = asRecord(finance.totals);
  const pushDispatch = asRecord(analytics.push_dispatch);
  const attendance = asRecord(analytics.attendance);
  const communication = asRecord(analytics.communication);
  const notificationClicks = asRecord(analytics.notification_clicks);
  const reviewByRating = asRecord(feedback.by_rating);
  const eventMix = readKpi(summaryQuery.data, "engagement.event_mix");
  const count = (value: number) => formatCount(uiLocale, value);

  return (
    <main className="min-h-screen bg-[var(--bg)] px-4 py-8 text-[var(--text)] sm:px-6 md:px-10 md:py-10">
      <div className="mx-auto max-w-6xl space-y-6">
        <PageHeader
          title={SECTION_TITLE[section]}
          actions={
            <BackLink href={adminHref("/admin/metrics", organizationSlug)} className={pageHeaderActionClass} style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
              {i18n("analyticsMarketing0ecf7f0")}
            </BackLink>
          }
        />

        <AnalyticsFilterBar
          filter={analyticsFilter.filter}
          onChange={analyticsFilter.setFilter}
          dimensions={SECTION_DIMENSIONS[section]}
          days={analyticsFilter.days}
          today={analyticsFilter.today}
          page={section}
        />

        {summaryQuery.error instanceof Error ? (
          <ErrorNotice>
            {localizeError(summaryQuery.error, i18n)}
          </ErrorNotice>
        ) : null}

        {summaryQuery.isLoading ? <p className="text-sm text-[var(--muted)]">{t("kpi.loading")}</p> : null}

        <KpiSections payload={summaryQuery.data} prefixes={SECTION_PREFIXES[section]} exclude={OWN_WIDGET} directory={directory} />

        <BranchSplits
          rows={payload.branches as BranchSplit[] | undefined}
          columns={[
            { key: "check_ins", label: branchT("checkIns"), format: (value) => formatCount(uiLocale, Number(value ?? 0)) },
            { key: "attended", label: branchT("attended"), format: (value) => formatCount(uiLocale, Number(value ?? 0)) },
            { key: "active_memberships", label: branchT("activeMemberships"), format: (value) => formatCount(uiLocale, Number(value ?? 0)) },
            { key: "paid_revenue_cents", label: i18n("paidRevenue64c34e5"), format: (value) => formatMoney(uiLocale, Number(value ?? 0)) },
          ]}
        />

        {section === "overview" ? <section className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <PlainTile
            label={i18n("paidRevenue64c34e5")}
            value={formatMoney(uiLocale, metricNumber(financeTotals, "paid_revenue_cents"))}
            detail={i18n("activeMembershipCount", { count: metricNumber(dashboardFinance, "active_memberships") })}
            helpPath="widgets.overview.paid_revenue"
            href={adminHref("/admin/metrics/finance", organizationSlug)}
          />
          <PlainTile label={i18n("reviewsb83c4cd")} value={count(metricNumber(feedback, "total"))} helpPath="widgets.overview.reviews" href={adminHref("/admin/reviews", organizationSlug)} />
          <PlainTile
            label={i18n("activeInjuriesdaecfa6")}
            value={count(metricNumber(wellbeing, "active_count"))}
            detail={i18n("totalReportCount", { count: metricNumber(wellbeing, "total") })}
            helpPath="widgets.overview.active_injuries"
            href={adminHref("/admin/metrics/health", organizationSlug)}
          />
          <PlainTile
            label={i18n("notificationClicks02c5775")}
            value={count(metricNumber(notificationClicks, "total"))}
            detail={i18n("trackedEventCount", { count: metricNumber(events, "total") })}
            helpPath="widgets.overview.notification_clicks"
            href={adminHref("/admin/metrics/engagement", organizationSlug)}
          />
        </section> : null}

        {section === "training" ? (
          <ExecutionKpiDashboard
            payload={summaryQuery.data}
            loading={summaryQuery.isLoading}
            since={readKpi(summaryQuery.data, "training.execution_kpis").since}
          />
        ) : null}

        {section === "training" ? <section id="training-analytics" className="scroll-mt-20 space-y-4">
          <h2 className="text-xl font-black">{i18n("teamWorkoutBreakdownLast30Days86ec3d2")}</h2>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
            <PlainTile label={i18n("teamCompletions2a732d2")} value={count(metricNumber(teamWorkoutsAggregate, "team_count"))} helpPath="widgets.training.team_completions" />
            <PlainTile
              label={i18n("individualCompletions70ee9b2")}
              value={count(metricNumber(teamWorkoutsAggregate, "individual_count"))}
              helpPath="widgets.training.individual_completions"
            />
            <PlainTile label={i18n("totalCompletionsfa16f4c")} value={count(metricNumber(teamWorkoutsAggregate, "total_count"))} helpPath="widgets.training.total_completions" />
          </div>
          {Object.keys(teamWorkoutsByUser).length > 0 ? (
            <div className="overflow-hidden rounded-2xl border border-[color:var(--border)] bg-[var(--panel)]">
              <p className="px-3 pt-3 text-xs font-bold uppercase tracking-[0.16em] text-[var(--muted)]">{i18n("perUser3fcfda7")}</p>
              <table className="w-full table-fixed text-start text-sm">
                <tbody>
                  {entries(teamWorkoutsByUser).slice(0, 8).map(([userId, value]) => (
                    <tr key={userId} className="border-t border-[color:var(--border)]">
                      <td className="truncate p-3 font-mono text-xs text-[var(--muted)]">{directory.staffName.get(userId) ?? userId}</td>
                      <td className="w-20 p-3 text-end font-bold">{count(Number(value))}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : null}
          <BreakdownList title={i18n("attendanceb689313")} rows={entries(asRecord(attendance.by_status))} helpPath="widgets.training.attendance_status" />
        </section> : null}

        {section === "engagement" ? <section id="user-engagement" className="scroll-mt-20 grid gap-4 lg:grid-cols-2">
          <EventMixList groups={eventMixGroups(events.by_category)} since={eventMix.since} />
          <BreakdownList title={i18n("pushDelivery52c03a7")} rows={entries(asRecord(pushDispatch.by_status))} helpPath="widgets.engagement.push_delivery" />
          <BreakdownList title={i18n("communicationade0d50")} rows={entries(asRecord(communication.by_direction))} helpPath="widgets.engagement.communication" />
          <BreakdownList title={i18n("reviewRatingsd575ce1")} rows={entries(reviewByRating)} helpPath="widgets.engagement.review_ratings" />
        </section> : null}

        {section === "coaching" ? <section id="coaching-analytics" className="scroll-mt-20 space-y-4">
          <div className="flex justify-end">
            <Link className="text-sm font-bold text-[var(--primary)]" href={adminHref("/admin/coaching-assignments", organizationSlug)}>
              {i18n("openPersonalCoachingf4be893")}
            </Link>
          </div>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
            <PlainTile label={i18n("activeAthletes78e231e")} value={count(metricNumber(coaching, "active_athletes"))} helpPath="widgets.coaching.active_athletes" />
            <PlainTile label={i18n("capturedEvents2551a14")} value={count(metricNumber(dashboardCoaching, "event_count"))} helpPath="widgets.coaching.captured_events" />
            <PlainTile label={i18n("reviewsb83c4cd")} value={count(metricNumber(dashboardCoaching, "review_count"))} helpPath="widgets.coaching.reviews" />
          </div>
        </section> : null}

        {section === "health" ? <section id="health-incidents" className="scroll-mt-20 space-y-4">
          <div className="flex justify-end">
            <Link className="text-sm font-bold text-[var(--primary)]" href={adminHref("/admin/wellbeing", organizationSlug)}>
              {i18n("openIncidentRecords7447df1")}
            </Link>
          </div>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
            <PlainTile label={i18n("activeInjuriesdaecfa6")} value={count(metricNumber(wellbeing, "active_count"))} helpPath="widgets.health.active_injuries" />
            <PlainTile label={i18n("totalReports5654449")} value={count(metricNumber(wellbeing, "total"))} helpPath="widgets.health.total_reports" />
            <PlainTile label={i18n("recentInjuryFlags0692c0a")} value={count(metricNumber(dashboardCoaching, "injury_count"))} helpPath="widgets.health.recent_injury_flags" />
          </div>
        </section> : null}

        {section === "overview" ? <section className="grid gap-4 lg:grid-cols-2">
          <WidgetCard label={i18n("operationalStatus1fdea4e")} helpPath="widgets.overview.operational_status">
            <dl className="space-y-4 text-sm">
              <div className="flex justify-between gap-4">
                <dt className="text-[var(--muted)]">{i18n("financeAggregated28a516")}</dt>
                <dd className="font-bold capitalize"><SemanticLabel value={metricText(dashboardFinance, "aggregate_status")} /></dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-[var(--muted)]">{i18n("lowRatingReviews928d645")}</dt>
                <dd className="font-bold">{count(metricNumber(crossContext, "low_rating_count"))}</dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-[var(--muted)]">{i18n("expiringMemberships522e6a4")}</dt>
                <dd className="font-bold">{count(metricNumber(dashboardFinance, "expiring_memberships"))}</dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-[var(--muted)]">{i18n("coachingActiveAthletese8bc87a")}</dt>
                <dd className="font-bold">{count(metricNumber(coaching, "active_athletes"))}</dd>
              </div>
            </dl>
          </WidgetCard>
        </section> : null}
      </div>
    </main>
  );
}
