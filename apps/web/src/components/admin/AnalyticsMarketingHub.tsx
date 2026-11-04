"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";

import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { PageHeader } from "@/components/PageHeader";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { AutomationsTab } from "@/components/admin/analytics/AutomationsTab";
import { MarketingTab } from "@/components/admin/analytics/MarketingTab";
import { SmsCostTab } from "@/components/channels/SmsCostTab";

export type AnalyticsTab = "overview" | "marketing" | "automations" | "sms";
const TABS: AnalyticsTab[] = ["overview", "marketing", "automations", "sms"];

export function analyticsTabFrom(value: string | null): AnalyticsTab {
  return TABS.find((tab) => tab === value) ?? "overview";
}

/**
 * Στατιστικά & Μάρκετινγκ (W3 navigation, ANR 2026-11-02): four tabs,
 * Επισκόπηση · Μάρκετινγκ · Αυτοματισμοί · Μηνύματα SMS, kept in `?tab=`.
 * Επισκόπηση is the hub of reports it always was; Μάρκετινγκ is the home of
 * challenges, promotions, partner perks and referrals (ANR 2026-11-04).
 */
export function AnalyticsMarketingHub() {
  const i18n = useUiTranslations();
  const t = useTranslations("Sms");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const tab = analyticsTabFrom(searchParams.get("tab"));

  const choose = (next: AnalyticsTab) => {
    const params = new URLSearchParams(searchParams.toString());
    if (next === "overview") params.delete("tab");
    else params.set("tab", next);
    const query = params.toString();
    router.replace(`${pathname}${query ? `?${query}` : ""}`, { scroll: false });
  };

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-8">
        <PageHeader title={i18n("analyticsMarketinga05588a")} />
        <SegmentPicker
          variant="track"
          ariaLabel={i18n("analyticsMarketinga05588a")}
          idPrefix="analytics"
          panelId="analytics-panel"
          value={tab}
          onChange={choose}
          options={[
            { value: "overview", label: i18n("overview0efc2e6") },
            { value: "marketing", label: i18n("marketinge0c534a") },
            { value: "automations", label: t("tabAutomations") },
            { value: "sms", label: t("tabSms") },
          ]}
        />
        <div id="analytics-panel" role="tabpanel" aria-labelledby={`analytics-tab-${tab}`}>
          {tab === "overview" ? <OverviewSections /> : null}
          {tab === "marketing" ? <MarketingTab /> : null}
          {tab === "automations" ? <AutomationsTab /> : null}
          {tab === "sms" && token ? <SmsCostTab token={token} /> : null}
        </div>
      </div>
    </main>
  );
}

function OverviewSections() {
  const i18n = useUiTranslations();
  const organizationSlug = useOrganizationSlug();
  const SECTIONS = [
    { title: i18n("overview0efc2e6"), description: i18n("crossDomainSignalsAndACompactViewOf0bf1ada"), href: "/admin/metrics/overview" },
    { title: i18n("financeAnalytics107dfa1"), description: i18n("membershipRevenuePackageRenewalAndRetentionReporting45d89f2"), href: "/admin/metrics/finance" },
    { title: i18n("trainingAnalytics2c25dde"), description: i18n("attendanceCompletionsWorkoutTypesAndPerformanceTrends77b2f11"), href: "/admin/metrics/training" },
    { title: i18n("coachingAnalyticsb6ddda1"), description: i18n("athleteActivityAdherenceAssignmentCompletionAndFollowUp144ce93"), href: "/admin/metrics/coaching" },
    { title: i18n("userEngagement72f61cf"), description: i18n("reviewsCommunicationNotificationsAndInteractionSignals6592ffe"), href: "/admin/metrics/engagement" },
    { title: i18n("healthIncidentsb8da1fe"), description: i18n("aggregateInjuryLimitationSeverityAndUnresolvedReportSignals1fecbcf"), href: "/admin/metrics/health" },
  ] as const;
  return (
    <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      {SECTIONS.map((section) => (
        <Link
          key={section.title}
          href={adminHref(section.href, organizationSlug)}
          className="group flex min-h-52 flex-col rounded-[2rem] p-6 transition-transform hover:-translate-y-0.5"
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        >
          <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>{section.title}</p>
          <p className="mt-4 flex-1 text-sm leading-6" style={{ color: "var(--muted)" }}>{section.description}</p>
          <p className="mt-5 text-sm font-semibold" style={{ color: "var(--text)" }}>
            {i18n("opencf9b770")} <span className="inline-block transition-transform group-hover:translate-x-1 rtl:rotate-180 rtl:group-hover:-translate-x-1">→</span>
          </p>
        </Link>
      ))}
    </section>
  );
}
