// ADR-364 / ADR-366: what the status page, the platform console and the
// in-app strip show. Pure, so the rules are unit tested.

export const STATUS_COMPONENTS = ["app", "search", "files", "email", "payments", "fiscal"] as const;
export type StatusComponentKey = (typeof STATUS_COMPONENTS)[number];

export type ComponentStatus = "operational" | "degraded" | "down" | "maintenance" | "unknown";
export type OverallStatus = "operational" | "degraded" | "partial_outage" | "major_outage" | "maintenance" | "unknown";
export type DayStatus = "operational" | "degraded" | "down" | "no_data";

/** The colour family of a state; every family maps to a theme token. */
export type Tone = "ok" | "warn" | "down" | "info" | "none";

export function componentTone(status: ComponentStatus | string): Tone {
  switch (status) {
    case "operational":
      return "ok";
    case "degraded":
      return "warn";
    case "down":
      return "down";
    case "maintenance":
      return "info";
    default:
      return "none";
  }
}

export function overallTone(status: OverallStatus | string): Tone {
  switch (status) {
    case "operational":
      return "ok";
    case "degraded":
    case "partial_outage":
      return "warn";
    case "major_outage":
      return "down";
    case "maintenance":
      return "info";
    default:
      return "none";
  }
}

export function dayTone(status: DayStatus | string): Tone {
  return status === "no_data" ? "none" : componentTone(status);
}

/** The theme colour of a tone (never a literal colour). */
export function toneColor(tone: Tone): string {
  switch (tone) {
    case "ok":
      return "var(--success)";
    case "warn":
      return "var(--warning)";
    case "down":
      return "var(--danger)";
    case "info":
      return "var(--primary)";
    default:
      return "var(--dim)";
  }
}

/** A day bar: success is softened so problem days stand out. */
export function dayBarColor(status: DayStatus | string): string {
  const tone = dayTone(status);
  if (tone === "ok") return "color-mix(in srgb, var(--success) 70%, var(--panel))";
  if (tone === "none") return "var(--panel-muted)";
  return toneColor(tone);
}

/** Mobile shows 30 days per component, desktop 90 (ANR, W7 screen 1). */
export const PHONE_DAYS = 30;
export const DESKTOP_DAYS = 90;

/** The last `count` days of a component's history, oldest first. */
export function lastDays<T>(days: T[], count: number): T[] {
  return days.length <= count ? days : days.slice(days.length - count);
}

/** Uptime over the shown days; null without data. Two decimals, as the page shows it. */
export function uptimeOver(days: Array<{ uptime_percent: number | null }>): number | null {
  const known = days.map((day) => day.uptime_percent).filter((value): value is number => typeof value === "number");
  if (known.length === 0) return null;
  const mean = known.reduce((sum, value) => sum + value, 0) / known.length;
  return Math.floor(mean * 100) / 100;
}

export function formatUptime(value: number, locale: string): string {
  return new Intl.NumberFormat(locale, {
    minimumFractionDigits: value === 100 ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(value);
}

type Translatable = {
  title: string;
  locale?: string | null;
  title_en?: string | null;
  en_source?: string | null;
  updates: Array<{ body: string; locale?: string | null; body_en?: string | null; en_source?: string | null }>;
};

function language(tag: string | null | undefined) {
  return tag ? tag.toLowerCase().split(/[-_]/)[0] : null;
}

/**
 * ADR-366: the reader sees the original when it is in their language (or
 * there is no English copy), else the English copy; `machine` marks an
 * untouched machine translation.
 */
export function incidentText(incident: Translatable, readerLocale: string) {
  const latest = incident.updates[0];
  const source = incident.locale ?? latest?.locale ?? null;
  const hasEnglish = Boolean(incident.title_en || latest?.body_en);
  const english = hasEnglish && language(readerLocale) !== language(source);
  return {
    title: english && incident.title_en ? incident.title_en : incident.title,
    body: latest ? (english && latest.body_en ? latest.body_en : latest.body) : null,
    machine: english && (latest?.en_source ?? incident.en_source) === "auto",
  };
}

/** Who uses which component, for the in-app strip (ADR-366). */
export type StatusViewer = {
  signedIn: boolean;
  /** Has at least one box membership (any role). */
  inBox: boolean;
  /** Is staff of a box that may issue fiscal documents. */
  fiscalStaff: boolean;
};

const FISCAL_ROLES = new Set(["owner", "admin", "front_desk", "accountant"]);

export function statusViewer(input: {
  signedIn: boolean;
  memberships: Array<{ role?: string | null; roles?: string[] | null }>;
}): StatusViewer {
  const roles = input.memberships.flatMap((membership) => [membership.role ?? "", ...(membership.roles ?? [])]);
  return {
    signedIn: input.signedIn,
    inBox: input.memberships.length > 0,
    fiscalStaff: roles.some((role) => FISCAL_ROLES.has(role)),
  };
}

/** Whether a component concerns the viewer: app, search, files and email concern everyone. */
export function usesComponent(component: string, viewer: StatusViewer): boolean {
  if (!viewer.signedIn) return false;
  if (component === "payments") return viewer.inBox;
  if (component === "fiscal") return viewer.fiscalStaff;
  return true;
}

type StripCandidate = { id: string; kind: string; impact: string; components: string[] };

/**
 * The incident the strip shows: the first active one (incidents before
 * maintenance) with an impact, naming a component the viewer uses. An
 * incident naming no component concerns everyone.
 */
export function stripIncident<T extends StripCandidate>(active: T[], viewer: StatusViewer): T | null {
  if (!viewer.signedIn) return null;
  const relevant = active.filter((incident) => {
    if (!incident || incident.impact === "none") return false;
    const components = Array.isArray(incident.components) ? incident.components : [];
    return components.length === 0 || components.some((component) => usesComponent(component, viewer));
  });
  return relevant.find((incident) => incident.kind === "incident") ?? relevant[0] ?? null;
}

/** The status page is served at the status host's root; everything else keeps its path. */
export function statusHostRewrite(hostname: string, pathname: string, statusHost: string): string | null {
  if (hostname.toLowerCase() !== statusHost.toLowerCase()) return null;
  return pathname === "/" || pathname === "" ? "/status" : null;
}
