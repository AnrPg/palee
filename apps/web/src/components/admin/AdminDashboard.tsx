"use client";







import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useEffect, useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";

import { type AdminChallengeRecord, fetchAdminChallenges } from "@/api/challenges";
import { fetchAdminAnalyticsSummary } from "@/api/analytics";
import { fetchFinanceQueues, fetchFinanceSummary, type FinanceRecord } from "@/api/finance";
import { fetchFiscalTransmissionCounts } from "@/api/fiscal";
import { fetchLandingPayload, type AdminMetrics } from "@/api/landing";
import { fetchSchedule } from "@/api/schedule";
import { fetchScalingQueue, SCALING_QUEUE_KEY } from "@/api/scaling";
import { fetchAppointmentSlots, fetchFormReviewQueue, fetchReplyQueue, type AppointmentSlot } from "@/api/staff";
import { FORM_REVIEWS_KEY } from "@/components/staff/FormReviewQueue";
import {
  COACH_QUEUE_HREFS,
  coachQueueCounts,
  mergeAgenda,
  openAppointmentSlots,
  slotsOnDay,
} from "@/components/admin/staff-home-agenda";
import { useSession } from "@/components/session-provider";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { PageHeader, pageHeaderActionClass } from "@/components/PageHeader";
import { InviteClientsButton } from "@/components/invites/InviteClients";
import { can, membershipRoles, staffNavItems, type MembershipLike } from "@/lib/role-navigation";
import { classesCoachedToday } from "@/components/admin/staff-home";
import { foldSingleTileGroups } from "@/components/admin/hub-groups";
import {
  CardLink,
  ClassTimeline,
  CountBadge,
  DashboardCard,
  EmptyNote,
  HubTiles,
  StatPill,
  type IconName,
  type TimelineEntry,
} from "@/components/admin/DashboardWidgets";
import { clockFormat } from "@/lib/clock";
import { earliestDateKey, formatDateKey } from "@/lib/local-date";
import { financeQueueHref } from "@/components/admin/finance/finance-queues";
import { useBusinessFeatures } from "@/lib/use-business-features";

type AlertCategory = "finance" | "coaching" | "training";
type AlertMessageKey =
  | "adminAlertExpiringMemberships"
  | "adminAlertOverdueInvoices"
  | "adminAlertPendingPayments"
  | "adminAlertFiscalNotReported"
  | "adminAlertPendingReferralRewards"
  | "adminAlertInjuryFlags"
  | "adminAlertUnreadWorkoutReviews"
  | "adminAlertPendingBookingApprovals"
  | "shAlertRepliesWaiting"
  | "shAlertFormReviews"
  | "shAlertScaling";

const DEFAULT_CATEGORIES: AlertCategory[] = ["finance", "coaching", "training"];
const STORAGE_KEY = "palee-admin-alert-categories";

function loadCategories(): AlertCategory[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_CATEGORIES;
    const parsed = JSON.parse(raw) as unknown;
    if (Array.isArray(parsed)) return parsed as AlertCategory[];
  } catch {}
  return DEFAULT_CATEGORIES;
}

function saveCategories(cats: AlertCategory[]) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(cats));
  } catch {}
}

function money(uiLocale: string, cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}

function formatDate(locale: string, iso: string) {
  return new Date(iso).toLocaleDateString(locale, { month: "short", day: "numeric" });
}

function isActiveChallenge(c: AdminChallengeRecord) {
  const now = Date.now();
  return new Date(c.starts_at).getTime() <= now && new Date(c.ends_at).getTime() >= now;
}

function AdminMetricChip({ label, value, href, danger = false, loading = false }: {
  label: string;
  value: string;
  href: string;
  danger?: boolean;
  loading?: boolean;
}) {
  
  return (
    <Link
      href={href}
      className="flex min-w-0 flex-col items-start gap-3 rounded-[1.6rem] p-4 transition-transform hover:-translate-y-0.5 sm:flex-row sm:items-center sm:gap-4"
      style={{
        background: "var(--panel)",
        border: `1px solid ${danger ? "color-mix(in srgb, var(--danger, var(--primary)) 30%, transparent)" : "var(--border)"}`,
      }}
    >
      <span
        className="grid h-14 w-14 shrink-0 place-items-center rounded-full p-[3px] sm:h-16 sm:w-16"
        style={{ background: `conic-gradient(${danger ? "var(--danger, var(--primary))" : "var(--primary)"} 0 78%, var(--border) 78% 100%)` }}
        aria-hidden="true"
      >
        <span className="grid h-full w-full place-items-center rounded-full text-sm font-bold sm:text-base" style={{ background: "var(--panel)", color: loading ? "var(--border)" : danger ? "var(--danger, var(--primary))" : "var(--text)" }}>
          {loading ? "…" : value}
        </span>
      </span>
      <span className="min-w-0 text-[11px] font-semibold uppercase tracking-[0.16em] sm:text-xs sm:tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</span>
    </Link>
  );
}

function AdminChallengeCard({ challenge }: { challenge: AdminChallengeRecord }) {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const pct = Math.round(challenge.progress_summary.completion_rate * 100);
  return (
    <article
      className="rounded-[1.6rem] p-5"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{challenge.title}</p>
          {challenge.description && (
            <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{challenge.description}</p>
          )}
          <p className="mt-1.5 text-xs" style={{ color: "var(--muted)" }}>
            {formatDate(uiLocale, challenge.starts_at)} – {formatDate(uiLocale, challenge.ends_at)}
          </p>
        </div>
        <span
          className="shrink-0 rounded-full px-2 py-1 text-[10px] font-semibold"
          style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary-strong)" }}
        >
          {challenge.badge_label}
        </span>
      </div>

      <div className="mt-4 h-1.5 overflow-hidden rounded-full" style={{ background: "var(--border)" }}>
        <div
          className="h-full rounded-full"
          style={{ width: (pct) + "%", background: pct === 100 ? "var(--success)" : "var(--primary)" }}
        />
      </div>

      <div className="mt-3 flex gap-4 text-xs" style={{ color: "var(--muted)" }}>
        <span>{i18n("challengeParticipantCount", { count: Number(challenge.progress_summary.participants ?? 0) })}</span>
        <span>{i18n("challengeCompletedCount", { count: Number(challenge.progress_summary.completed ?? 0) })}</span>
        <span>{i18n("challengeCompletionRate", { rate: pct / 100 })}</span>
      </div>
    </article>
  );
}

type DashboardLink = { label: string; href: string; icon: IconName; show?: boolean };

/**
 * The staff dashboard. Every staff role gets this page (ADR-103 keeps the
 * existing UI): tiles, alerts and links a membership cannot open are hidden.
 * Without a membership everything shows.
 *
 * Layout B (ANR, 2026-11-03): the order answers "what do I set up, what do I
 * have today, what waits for me, who are my people", then every tool.
 * - `setup`: the box set-up card, first, while it is still to do.
 * - «Σήμερα»: today's classes, plus the coach's own appointments when
 *   `appointments` is on, in one list by time.
 * - «Θέλει προσοχή»: one list; with `coachQueues` it also counts the coach's
 *   unanswered messages, technique videos and scaling suggestions, each a row
 *   that opens its tab in the coaching workspace (no separate cards).
 * - `children`: role cards (front desk, accounts, cleaning…).
 * - `people`: «Οι άνθρωποί σου» (member search, clients, coach groups).
 */
export function AdminDashboard({
  membership,
  setup,
  people,
  coachQueues = false,
  appointments = false,
  children,
}: {
  membership?: MembershipLike | null;
  setup?: ReactNode;
  people?: ReactNode;
  coachQueues?: boolean;
  appointments?: boolean;
  children?: ReactNode;
} = {}) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const nav = useTranslations("Navigation");
  const standingT = useTranslations("MemberStanding");
  const publicPageT = useTranslations("AdminPublicPage");
  const documentsT = useTranslations("Documents");
  const has = (...capabilities: string[]) =>
    membership === undefined || capabilities.some((capability) => can(membership, capability));
  const fullAnalytics = has("view_business_analytics");
  const canFinancePage = has("take_payments", "manage_billing", "view_finance_reports");
  const ALL_NAV_GROUPS: Array<{ label: string; items: DashboardLink[] }> = [
    {
      label: i18n("operationsa1fdaa6"),
      items: [
        { label: i18n("users57f2b18"), href: "/admin/users", icon: "users", show: has("view_directory", "view_billing_contacts") },
        { label: nav("trials"), href: "/admin/trials", icon: "users", show: has("run_classes", "manage_memberships", "manage_settings") },
        { label: nav("community"), href: "/admin/community", icon: "users", show: has("moderate_community") },
        { label: i18n("finance1b48d3f"), href: "/admin/finance", icon: "wallet", show: canFinancePage },
        // Shop proposal §2 (A): «Κατάστημα» is its own section; TODO(ADR-190) `manage_shop`.
        { label: nav("shop"), href: "/admin/shop", icon: "bag", show: has("manage_shop") || has("sell_shop") },
        { label: i18n("classesed1846a"), href: "/admin/class-schedule", icon: "calendar", show: has("run_classes", "manage_schedule", "manage_coaching") },
        { label: i18n("admCheckInTitle"), href: "/admin/check-in", icon: "check", show: has("check_in") },
        { label: i18n("personalCoaching6accdcd"), href: "/admin/coaching-assignments", icon: "coach", show: has("manage_coaching") },
        { label: nav("appointments"), href: "/admin/appointments", icon: "clock", show: has("manage_appointments") },
        { label: nav("cleaningLog"), href: "/admin/cleaning", icon: "sparkle", show: has("record_cleaning", "review_cleaning", "manage_cleaning_areas") },
        { label: nav("inventory"), href: "/admin/inventory", icon: "box", show: has("report_inventory", "manage_inventory") },
        // ADR-202: the gym's spaces, their floor plans and unavailability.
        { label: nav("spaces"), href: "/admin/spaces", icon: "box", show: has("view_spaces", "manage_spaces", "edit_space_details", "set_space_unavailable") },
      ],
    },
    {
      // «Περιεχόμενο» (ANR, 2026-11-03): what the box writes and publishes.
      // The pages keep their own places; these are only shortcuts.
      label: i18n("content4f9be05"),
      items: [
        { label: nav("wodsVault"), href: "/admin/workouts", icon: "dumbbell", show: has("manage_workouts") },
        { label: i18n("rhNutritionPlans"), href: "/admin/coaching?tab=nutrition", icon: "leaf", show: has("manage_coaching") },
        { label: nav("onDemandContent"), href: "/admin/content", icon: "play", show: has("manage_content") },
        { label: publicPageT("navLabel"), href: "/admin/public-page", icon: "star", show: has("manage_settings") },
        // ADR-252 §7: documents for settings, membership and front-desk staff.
        { label: documentsT("title"), href: "/admin/documents", icon: "file", show: has("manage_settings", "manage_memberships", "request_signatures") },
      ],
    },
    {
      label: i18n("analyticsMarketinga05588a"),
      items: [
        { label: i18n("overview0efc2e6"), href: "/admin/metrics", icon: "chart", show: fullAnalytics },
        { label: i18n("rhCoachingReports"), href: "/admin/metrics/coaching", icon: "chart", show: !fullAnalytics && has("view_coaching_analytics") },
        { label: i18n("rhFinanceReports"), href: "/admin/metrics/finance", icon: "file", show: !fullAnalytics && has("view_finance_reports") },
        { label: i18n("challengesff38765"), href: "/admin/challenges", icon: "trophy", show: has("manage_challenges") },
        { label: i18n("reviewsb83c4cd"), href: "/admin/reviews", icon: "star", show: has("view_feedback") },
        { label: i18n("healthIncidentsb8da1fe"), href: "/admin/wellbeing", icon: "heart", show: has("view_health") },
      ],
    },
  ];
  const NAV_GROUPS = foldSingleTileGroups(
    ALL_NAV_GROUPS.map((group) => ({
      ...group,
      items: group.items.filter((item) => item.show !== false),
    })),
  );
  // Header shortcuts (ANR, 2026-11-03): never a page the top bar already
  // links to (Οικονομικά, Coaching… sit there), so the header offers the next
  // most used pages instead: check-in, analytics, the shop or else spaces.
  const topBarHrefs = new Set(membership ? staffNavItems(membership).map((item) => item.href) : []);
  const headerShortcuts = [
    { href: "/admin/check-in", label: nav("checkIn"), show: has("check_in") },
    { href: "/admin/metrics", label: i18n("analyticsMarketinga05588a"), show: fullAnalytics },
    { href: "/admin/shop", label: nav("shop"), show: has("manage_shop") || has("sell_shop") },
    { href: "/admin/spaces", label: nav("spaces"), show: has("view_spaces", "manage_spaces", "edit_space_details", "set_space_unavailable") },
  ]
    .filter((shortcut) => shortcut.show && !topBarHrefs.has(shortcut.href))
    .slice(0, 3);
  const canFinanceReports = has("view_finance_reports");
  const features = useBusinessFeatures();
  const canBusinessAnalytics = fullAnalytics;
  const canChallenges = has("manage_challenges");
  const canClasses = has("run_classes", "manage_schedule", "manage_coaching");
  const { tokens, currentUser } = useSession();
  const organizationSlug = useOrganizationSlug();
  const [configOpen, setConfigOpen] = useState(false);
  const [activeCategories, setActiveCategories] = useState<AlertCategory[]>(DEFAULT_CATEGORIES);

  useEffect(() => {
    queueMicrotask(() => setActiveCategories(loadCategories()));
  }, []);

  const token = tokens?.access_token;
  const enabled = Boolean(token);

  const financeQuery = useQuery({
    queryKey: ["admin", "dashboard", "finance-summary"],
    enabled: enabled && canFinanceReports,
    queryFn: () => fetchFinanceSummary(token!),
  });

  const queuesQuery = useQuery({
    queryKey: ["admin", "dashboard", "queues"],
    enabled: enabled && canFinanceReports,
    queryFn: () => fetchFinanceQueues(token!, { expires_within_days: "30" }),
  });

  // ADR-530: documents the tax authority refused or that ran out of attempts.
  const transmissionsQuery = useQuery({
    queryKey: ["admin", "dashboard", "fiscal-transmissions"],
    enabled: enabled && canFinanceReports,
    queryFn: () => fetchFiscalTransmissionCounts(token!),
  });

  const analyticsQuery = useQuery({
    queryKey: ["admin", "dashboard", "analytics"],
    enabled: enabled && canBusinessAnalytics,
    queryFn: () => fetchAdminAnalyticsSummary(token!),
  });

  const scheduleQuery = useQuery({
    queryKey: ["admin", "dashboard", "schedule"],
    enabled: enabled && canClasses,
    queryFn: () => {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const endDate = new Date(today);
      endDate.setDate(today.getDate() + 7);
      return fetchSchedule(token!, {
        startAt: today.toISOString(),
        endAt: endDate.toISOString(),
        days: 7,
        classTypeIds: [],
      });
    },
  });

  const landingQuery = useQuery({
    queryKey: ["admin", "dashboard", "landing"],
    enabled,
    queryFn: () => fetchLandingPayload(token!),
    staleTime: 2 * 60 * 1000,
  });

  const challengesQuery = useQuery({
    queryKey: ["admin", "dashboard", "challenges"],
    enabled: enabled && canChallenges,
    queryFn: () => fetchAdminChallenges(token!),
    staleTime: 5 * 60 * 1000,
  });

  const replyQueueQuery = useQuery({
    queryKey: ["staff", "reply-queue"],
    enabled: enabled && coachQueues,
    queryFn: () => fetchReplyQueue(token!),
    refetchInterval: 60_000,
  });

  const formReviewsQuery = useQuery({
    queryKey: [...FORM_REVIEWS_KEY, "submitted"],
    enabled: enabled && coachQueues,
    queryFn: () => fetchFormReviewQueue(token!, "submitted"),
  });

  const scalingQuery = useQuery({
    queryKey: SCALING_QUEUE_KEY,
    enabled: enabled && coachQueues,
    queryFn: () => fetchScalingQueue(token!),
    staleTime: 60_000,
  });

  const appointmentsQuery = useQuery({
    queryKey: ["staff", "home", "appointments", currentUser?.id],
    enabled: enabled && appointments && Boolean(currentUser?.id),
    queryFn: () => {
      const from = new Date();
      from.setHours(0, 0, 0, 0);
      const to = new Date(from);
      to.setDate(from.getDate() + 7);
      return fetchAppointmentSlots(token!, { from: from.toISOString(), to: to.toISOString(), coach_id: currentUser!.id });
    },
  });

  const totals = (financeQuery.data?.totals ?? {}) as FinanceRecord;
  const queues = (queuesQuery.data?.queues ?? {}) as Record<string, FinanceRecord[]>;
  const coaching = ((analyticsQuery.data as FinanceRecord)?.coaching ?? {}) as FinanceRecord;
  const slots = scheduleQuery.data?.slots ?? [];
  const adminMetrics = (landingQuery.data?.admin_metrics ?? null) as AdminMetrics | null;
  const activeChallenges = (challengesQuery.data?.challenges ?? []).filter(isActiveChallenge);

  const pendingBookingsCount = slots.reduce(
    (sum, slot) => sum + (slot.bookings ?? []).filter((b) => b.status === "pending").length,
    0,
  );

  const financeLoading = financeQuery.isLoading;
  const landingLoading = landingQuery.isLoading;

  // ── KPI rows ──────────────────────────────────────────────────────────────
  const financeKpis: Array<[string, string, boolean, string]> = [
    [i18n("activeMembersa17ecbe"), String(totals.active_memberships ?? 0), false, "/admin/finance"],
    [i18n("revenueMtd3ffc292"), money(uiLocale, totals.paid_revenue_cents), false, "/admin/metrics/finance"],
    [i18n("expiring30d1d039ba"), String(totals.expiring_memberships ?? 0), Number(totals.expiring_memberships ?? 0) > 0, financeQueueHref("expiring")],
    [i18n("overdueInvoices747a2d8"), money(uiLocale, totals.overdue_invoice_balance_cents), Number(totals.overdue_invoice_balance_cents ?? 0) > 0, financeQueueHref("debts")],
  ];

  const operationalKpis: Array<[string, string, boolean, string, boolean]> = [
    // ADR-470: referral approvals only with a referral programme, or while some still wait.
    [i18n("pendingApprovals6ac383a"), String(adminMetrics?.pending_referral_approvals ?? 0), Number(adminMetrics?.pending_referral_approvals ?? 0) > 0, "/admin/finance?tab=referrals", canFinanceReports && features.shows("referrals", Number(adminMetrics?.pending_referral_approvals ?? 0))],
    [i18n("totalOutstandingefd930a"), money(uiLocale, adminMetrics?.total_outstanding_cents ?? 0), Number(adminMetrics?.total_outstanding_cents ?? 0) > 0, "/admin/finance", canFinanceReports],
    [i18n("members1cb449c"), String(adminMetrics?.member_count ?? 0), false, "/admin/users", has("view_directory", "view_billing_contacts")],
  ];
  // admin_metrics only comes back for gym managers; other roles skip the row.
  const visibleOperationalKpis = adminMetrics || landingLoading ? operationalKpis.filter((kpi) => kpi[4]) : [];

  // ── Alerts ─────────────────────────────────────────────────────────────────
  // Each alert is one ICU plural message with the count inside it, so every
  // locale controls spacing, word order and plural forms (never `count + text`).
  // Every alert links to the list that holds the rows it counts, already
  // picked, and a money alert names its nearest date («λήξη 28 Οκτ 2026»).
  type DashboardAlert = { text: string; href: string; detail?: string | null; urgent?: boolean };
  const alertsFor = (
    rows: Array<[count: number, key: AlertMessageKey, href: string, detail?: string | null]>,
  ): DashboardAlert[] =>
    rows.filter(([count]) => count > 0).map(([count, key, href, detail]) => ({ text: i18n(key, { count }), href, detail }));
  const dueSince = (rows: FinanceRecord[] | undefined, field: string) => {
    const date = formatDateKey(uiLocale, earliestDateKey((rows ?? []).map((row) => row[field])));
    return date ? standingT("dueSince", { date }) : null;
  };
  const expiresOn = (rows: FinanceRecord[] | undefined) => {
    const date = formatDateKey(uiLocale, earliestDateKey((rows ?? []).map((row) => row.expires_on)));
    return date ? `${i18n("expiresa99be3d")} ${date}` : null;
  };

  const financeAlerts = alertsFor([
    [Number(totals.expiring_memberships ?? 0), "adminAlertExpiringMemberships", financeQueueHref("expiring"), expiresOn(queues.expiring_memberships)],
    [(queues.overdue_invoices ?? []).length, "adminAlertOverdueInvoices", financeQueueHref("debts"), dueSince(queues.overdue_invoices, "due_date")],
    [(queues.pending_payments ?? []).length, "adminAlertPendingPayments", financeQueueHref("debts")],
    [notReportedCount(transmissionsQuery.data), "adminAlertFiscalNotReported", "/admin/finance?tab=documents"],
    [(queues.pending_referral_rewards ?? []).length, "adminAlertPendingReferralRewards", "/admin/finance?tab=referrals"],
  ]);

  const coachingAlerts = alertsFor([
    [Number(coaching.injury_count ?? 0), "adminAlertInjuryFlags", "/admin/wellbeing"],
    [Number(coaching.review_count ?? 0), "adminAlertUnreadWorkoutReviews", "/admin/reviews"],
  ]);

  const queueCounts = coachQueueCounts({
    replies: replyQueueQuery.data,
    formReviews: formReviewsQuery.data,
    scaling: scalingQuery.data,
  });
  const coachQueueAlerts: DashboardAlert[] = coachQueues
    ? alertsFor([
        [
          queueCounts.replies,
          "shAlertRepliesWaiting",
          COACH_QUEUE_HREFS.replies,
          queueCounts.overdueReplies > 0 ? i18n("shAlertRepliesOverdue", { count: queueCounts.overdueReplies }) : null,
        ],
        [queueCounts.formReviews, "shAlertFormReviews", COACH_QUEUE_HREFS.formReviews],
        [queueCounts.scaling, "shAlertScaling", COACH_QUEUE_HREFS.scaling],
      ]).map((alert, index) => ({ ...alert, urgent: index === 0 && queueCounts.overdueReplies > 0 }))
    : [];

  const trainingAlerts = alertsFor([
    [pendingBookingsCount, "adminAlertPendingBookingApprovals", "/admin/class-schedule"],
  ]);

  const allAlerts: Record<AlertCategory, { label: string; items: DashboardAlert[] }> = {
    finance: { label: i18n("finance1b48d3f"), items: canFinanceReports ? financeAlerts : [] },
    coaching: { label: i18n("coachingfd8b79f"), items: [...coachQueueAlerts, ...(canBusinessAnalytics ? coachingAlerts : [])] },
    training: { label: i18n("trainingb6fe7f5"), items: has("run_classes") ? trainingAlerts : [] },
  };

  const hasAnyAlert = activeCategories.some((cat) => allAlerts[cat].items.length > 0);
  const hasAnyAvailableAlert = Object.values(allAlerts).some((group) => group.items.length > 0);
  const alertsLoading =
    financeQuery.isLoading ||
    queuesQuery.isLoading ||
    analyticsQuery.isLoading ||
    scheduleQuery.isLoading ||
    replyQueueQuery.isLoading ||
    formReviewsQuery.isLoading ||
    scalingQuery.isLoading;

  // ── Today ───────────────────────────────────────────────────────────────────
  const roles = membershipRoles(membership);
  // A coach who does not run the schedule sees the classes they coach.
  const mineOnly = membership !== undefined && roles.includes("coach") && !has("manage_schedule");
  const now = new Date();
  const todaySlots = (mineOnly
    ? classesCoachedToday(slots as Array<(typeof slots)[number] & { coach_user_id?: string | null }>, currentUser?.id, now)
    : slots.filter((slot) => new Date(slot.scheduled_at).toDateString() === now.toDateString())
  ).sort((a, b) => a.scheduled_at.localeCompare(b.scheduled_at));
  const timeFormat = clockFormat(uiLocale, { timeStyle: "short" });
  const classEntries = todaySlots.map((slot) => ({
    startsAt: slot.scheduled_at,
    entry: {
      id: slot.id,
      time: timeFormat.format(new Date(slot.scheduled_at)),
      title: slot.name,
      href: adminHref(`/admin/class-schedule?open_slot=${slot.id}`, organizationSlug),
      caption: i18n("rhBookedCount", { count: slot.approved_booking_count ?? 0, capacity: slot.capacity ?? 0 }),
      filled: slot.approved_booking_count ?? 0,
      capacity: slot.capacity ?? 0,
      past: new Date(slot.scheduled_at).getTime() + 60 * 60 * 1000 < now.getTime(),
    } as TimelineEntry,
  }));
  // The coach's own appointments for the coming week; today's join the agenda.
  const weekAppointments = appointments ? openAppointmentSlots<AppointmentSlot>(appointmentsQuery.data) : [];
  const appointmentsHref = adminHref("/admin/appointments", organizationSlug);
  const appointmentEntries = slotsOnDay(weekAppointments, now).map((slot) => {
    const booked = (slot.bookings ?? []).filter((booking) => booking.status === "booked");
    const names = booked.map((booking) => booking.nickname).filter(Boolean).join(", ");
    const kindLabel = slot.kind === "pt_session" ? i18n("stfKindPtSession") : i18n("stfKindAssessment");
    return {
      startsAt: slot.starts_at,
      entry: {
        id: `appointment-${slot.id}`,
        time: timeFormat.format(new Date(slot.starts_at)),
        title: names ? `${kindLabel} · ${names}` : kindLabel,
        href: appointmentsHref,
        caption: i18n("rhBookedCount", { count: booked.length, capacity: slot.capacity }),
        filled: booked.length,
        capacity: slot.capacity,
        past: new Date(slot.starts_at).getTime() + 60 * 60 * 1000 < now.getTime(),
      } as TimelineEntry,
    };
  });
  const showKinds = appointments && classEntries.length > 0 && appointmentEntries.length > 0;
  const timeline: TimelineEntry[] = mergeAgenda(classEntries, appointmentEntries).map((item) =>
    showKinds
      ? {
          ...item.entry,
          kind:
            item.kind === "class"
              ? { label: i18n("shAgendaClass"), tone: "class" as const }
              : { label: i18n("shAgendaAppointment"), tone: "appointment" as const },
        }
      : item.entry,
  );
  const showToday = canClasses || appointments;
  const todayLoading = (canClasses && scheduleQuery.isLoading) || (appointments && appointmentsQuery.isLoading);
  const showAttention = alertsLoading || hasAnyAvailableAlert;

  function toggleCategory(cat: AlertCategory) {
    const next = activeCategories.includes(cat)
      ? activeCategories.filter((c) => c !== cat)
      : [...activeCategories, cat];
    setActiveCategories(next);
    saveCategories(next);
  }

  return (
    <main
      className="min-h-screen px-4 py-8 sm:px-6 md:px-10 md:py-12"
      style={{
        backgroundColor: "var(--bg)",
        backgroundImage: "linear-gradient(color-mix(in srgb, var(--border) 35%, transparent) 1px, transparent 1px), linear-gradient(90deg, color-mix(in srgb, var(--border) 35%, transparent) 1px, transparent 1px)",
        backgroundSize: "32px 32px",
      }}
    >
      <div className="mx-auto max-w-6xl space-y-6 md:space-y-8">

        {/* Hero */}
        <div className="space-y-2">
          <div className="flex items-center justify-between gap-3">
            <p className="truncate text-xs font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary-strong)" }}>
              {i18n("todayAtAGlance07e2821")}
            </p>
            {has("manage_settings") ? (
              <Link
                aria-label={i18n("appConfigurationse0effaa")}
                href={adminHref("/admin/settings", organizationSlug)}
                title={i18n("appConfigurationse0effaa")}
                className="group flex items-center overflow-hidden rounded-full px-3 py-2 text-sm font-semibold"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
              >
                <span aria-hidden="true" className="text-xl leading-5">⚙</span>
                <span className="max-w-0 overflow-hidden whitespace-nowrap opacity-0 transition-all duration-200 group-hover:ms-2 group-hover:max-w-40 group-hover:opacity-100 group-focus-visible:ms-2 group-focus-visible:max-w-40 group-focus-visible:opacity-100">
                  {i18n("appConfigurationse0effaa")}
                </span>
              </Link>
            ) : null}
          </div>
          <PageHeader
            title={i18n("dashboardd87f47b")}
            actions={
              <>
                {has("invite_clients") ? <InviteClientsButton /> : null}
                {headerShortcuts.map((shortcut) => (
                  <Link
                    key={shortcut.href}
                    href={adminHref(shortcut.href, organizationSlug)}
                    data-testid="home-header-shortcut"
                    className={pageHeaderActionClass}
                    style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
                  >
                    {shortcut.label}
                  </Link>
                ))}
              </>
            }
          />
        </div>

        {/* Box set-up comes first while it is still to do */}
        {setup}

        {/* Headline KPIs: four at most */}
        {canFinanceReports ? (
          <section className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
            {financeKpis.map(([label, value, warn, href]) => (
              <AdminMetricChip key={label} label={label} value={value} href={adminHref(href, organizationSlug)} danger={warn} loading={financeLoading} />
            ))}
          </section>
        ) : null}

        {/* Secondary metrics, compact */}
        {visibleOperationalKpis.length > 0 ? (
          <section className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            {visibleOperationalKpis.map(([label, value, warn, href]) => (
              <StatPill key={label} label={label} value={value} href={adminHref(href, organizationSlug)} warn={warn} loading={landingLoading} />
            ))}
          </section>
        ) : null}

        {/* Today and what needs attention */}
        {showToday || showAttention ? (
          <div className={`grid gap-6 ${showToday && showAttention ? "lg:grid-cols-5" : ""}`}>
            {showToday ? (
              <DashboardCard
                id="home-today"
                eyebrow={appointments ? i18n("today24345a1") : mineOnly ? i18n("rhMyClassesToday") : i18n("classesTodayd01b776")}
                badge={!todayLoading ? <CountBadge value={timeline.length} tone={timeline.length ? "primary" : "neutral"} /> : null}
                action={
                  canClasses ? (
                    <CardLink href={adminHref("/admin/class-schedule", organizationSlug)}>{i18n("managebfa0df1")}</CardLink>
                  ) : (
                    <CardLink href={appointmentsHref}>{i18n("open6f4789b")}</CardLink>
                  )
                }
                className={showAttention ? "lg:col-span-3" : ""}
              >
                {todayLoading ? (
                  <div className="space-y-3">
                    {[1, 2].map((n) => (
                      <div key={n} className="h-16 animate-pulse rounded-[1.3rem]" style={{ background: "var(--border)" }} />
                    ))}
                  </div>
                ) : timeline.length === 0 ? (
                  <EmptyNote>
                    {appointments ? i18n("shNothingToday") : mineOnly ? i18n("rhClassesTodayCount", { count: 0 }) : i18n("dashNoClassesToday")}
                  </EmptyNote>
                ) : (
                  <ClassTimeline entries={timeline} />
                )}
                {appointments && canClasses && !todayLoading ? (
                  <Link
                    href={appointmentsHref}
                    data-testid="home-week-appointments"
                    className="mt-3 inline-block text-xs font-semibold hover:underline"
                    style={{ color: "var(--muted)" }}
                  >
                    {i18n("rhAppointmentsThisWeek", { count: weekAppointments.length })} →
                  </Link>
                ) : null}
              </DashboardCard>
            ) : null}

            {showAttention ? (
              <section id="home-attention" className={`rounded-[2.2rem] p-6 ${showToday ? "lg:col-span-2" : ""}`} style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <div className="flex items-center justify-between gap-4">
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>{i18n("needsAttentiona126722")}</p>
                    {!hasAnyAlert && !alertsLoading && (
                      <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>{i18n("noUrgentItemsAllClearbc87c03")}</p>
                    )}
                  </div>
                  <button
                    className="rounded-full px-4 py-2 text-xs font-semibold"
                    style={{ background: "var(--border)", color: "var(--text-soft)" }}
                    onClick={() => setConfigOpen((v) => !v)}
                    type="button"
                  >
                    {configOpen ? i18n("donee9b450d") : i18n("configure09054e5")}
                  </button>
                </div>

                {configOpen && (
                  <div className="mt-4 flex flex-wrap gap-2 rounded-[1.4rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                    <p className="w-full text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                      {i18n("showAlertCategoriesfc2cff7")}
                    </p>
                    {(["finance", "coaching", "training"] as AlertCategory[]).map((cat) => (
                      <button
                        key={cat}
                        aria-pressed={activeCategories.includes(cat)}
                        className="rounded-full px-4 py-2 text-sm font-semibold"
                        style={{
                          background: activeCategories.includes(cat) ? "var(--text)" : "var(--border)",
                          color: activeCategories.includes(cat) ? "var(--bg)" : "var(--dim)",
                        }}
                        onClick={() => toggleCategory(cat)}
                        type="button"
                      >
                        {allAlerts[cat].label}
                      </button>
                    ))}
                  </div>
                )}

                <div className="mt-5 space-y-4">
                  {activeCategories.map((cat) => {
                    const group = allAlerts[cat];
                    if (group.items.length === 0) return null;
                    return (
                      <div key={cat}>
                        <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{group.label}</p>
                        <ul className="mt-2 space-y-2">
                          {group.items.map((alert) => (
                            <li key={alert.text}>
                              <Link
                                href={adminHref(alert.href, organizationSlug)}
                                className="flex items-center gap-3 rounded-[1rem] px-4 py-3 text-sm transition-opacity hover:opacity-80"
                                style={{ background: "color-mix(in srgb, var(--primary) 7%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 15%, transparent)" }}
                              >
                                <span aria-hidden="true" className="h-2 w-2 shrink-0 rounded-full" style={{ background: alert.urgent ? "var(--danger)" : "var(--primary)" }} />
                                <span className="min-w-0 flex-1" style={{ color: "var(--text)" }}>
                                  {alert.text}
                                  {alert.detail ? (
                                    <span className="block text-xs" data-testid="alert-detail" style={{ color: "var(--muted)" }}>{alert.detail}</span>
                                  ) : null}
                                </span>
                                <span aria-hidden="true" style={{ color: "var(--primary-strong)" }}>→</span>
                              </Link>
                            </li>
                          ))}
                        </ul>
                      </div>
                    );
                  })}
                </div>
              </section>
            ) : null}
          </div>
        ) : null}

        {/* Role sections (front desk, accounts, cleaning…) */}
        {children ? <div className="grid items-stretch gap-6 md:grid-cols-2 md:[&>*:only-child]:col-span-2">{children}</div> : null}

        {/* «Οι άνθρωποί σου» */}
        {people}

        {/* Seasonal challenges, only while one runs; «Challenges» stays a tool below */}
        {canChallenges && activeChallenges.length > 0 ? (
          <DashboardCard
            eyebrow={i18n("seasonalChallengesfd69ec6")}
            title={i18n("activeChallengeCount", { count: activeChallenges.length })}
            action={<CardLink href={adminHref("/admin/challenges", organizationSlug)}>{i18n("managebfa0df1")}</CardLink>}
          >
            <div className="grid gap-3 sm:grid-cols-2">
              {activeChallenges.map((c) => (
                <AdminChallengeCard key={c.id} challenge={c} />
              ))}
            </div>
          </DashboardCard>
        ) : null}

        {/* Everything else this role can open */}
        {NAV_GROUPS.length > 0 ? (
          <HubTiles
            groups={NAV_GROUPS.map((group) => ({
              label: group.label,
              items: group.items.map((item) => ({ label: item.label, icon: item.icon, href: adminHref(item.href, organizationSlug) })),
            }))}
          />
        ) : null}

      </div>
    </main>
  );
}

/** ADR-530: reports that need someone (refused, or out of attempts); malformed answers count none. */
export function notReportedCount(list: { counts?: Record<string, number> } | undefined): number {
  const counts = list && typeof list.counts === "object" && list.counts ? list.counts : {};
  return (Number(counts.rejected) || 0) + (Number(counts.failed) || 0);
}
