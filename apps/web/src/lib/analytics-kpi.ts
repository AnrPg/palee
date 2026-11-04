/**
 * ADR-462: the staff KPIs as the summaries return them (`kpis`, keyed by the
 * metric registry key), read defensively, plus how each one is shown: its
 * unit, whether a reset applies, and which way is better.
 */

export type KpiUnit = "count" | "percent" | "ratio" | "cents" | "days" | "per_1000" | "rows";
export type KpiKind = "flow" | "snapshot" | "breakdown";

export type KpiRow = { key: string | number | null; suppressed: boolean } & Record<string, unknown>;

export type Kpi = {
  key: string;
  unit: KpiUnit;
  kind: KpiKind;
  value: number | null;
  previous: number | null;
  delta: number | null;
  since: string | null;
  suppressed: boolean;
  previousSuppressed: boolean;
  rows: KpiRow[];
};

/** Mirrors `Palee.Analytics.Domain.MetricRegistry` (scope organization). */
export const STAFF_METRICS: Record<string, { unit: KpiUnit; kind: KpiKind }> = {
  "overview.active_members": { unit: "count", kind: "snapshot" },
  "overview.net_member_change": { unit: "count", kind: "flow" },
  "overview.new_members": { unit: "count", kind: "flow" },
  "overview.churn_rate": { unit: "percent", kind: "flow" },
  "overview.trial_conversion": { unit: "percent", kind: "flow" },
  "overview.members_at_risk": { unit: "count", kind: "snapshot" },
  "training.class_fill_rate": { unit: "percent", kind: "flow" },
  "training.no_show_rate": { unit: "percent", kind: "flow" },
  "training.late_cancellations": { unit: "count", kind: "flow" },
  "training.waitlist_conversion": { unit: "percent", kind: "flow" },
  "training.visits_per_member_week": { unit: "ratio", kind: "flow" },
  "training.attendance_by_hour": { unit: "rows", kind: "breakdown" },
  "training.attendance_by_weekday": { unit: "rows", kind: "breakdown" },
  "training.execution_kpis": { unit: "rows", kind: "flow" },
  "coaching.classes_per_coach": { unit: "rows", kind: "breakdown" },
  "coaching.athletes_per_coach": { unit: "rows", kind: "snapshot" },
  "coaching.programme_adherence": { unit: "percent", kind: "flow" },
  "coaching.review_rating_per_coach": { unit: "rows", kind: "breakdown" },
  "engagement.weekly_active_users": { unit: "count", kind: "flow" },
  "engagement.challenge_participation": { unit: "percent", kind: "flow" },
  "engagement.booking_streaks": { unit: "count", kind: "flow" },
  "engagement.event_mix": { unit: "rows", kind: "breakdown" },
  "health.injuries_per_1000_attendances": { unit: "per_1000", kind: "flow" },
  "health.mean_recovery_days": { unit: "days", kind: "flow" },
  "health.top_body_areas": { unit: "rows", kind: "breakdown" },
  "finance.mrr": { unit: "cents", kind: "snapshot" },
  "finance.arpm": { unit: "cents", kind: "flow" },
  "finance.ltv": { unit: "cents", kind: "flow" },
  "finance.on_time_collection": { unit: "percent", kind: "flow" },
  "finance.days_sales_outstanding": { unit: "days", kind: "flow" },
  "finance.revenue_per_package": { unit: "rows", kind: "breakdown" },
  "demographics.age_bands": { unit: "rows", kind: "snapshot" },
  "demographics.genders": { unit: "rows", kind: "snapshot" },
};

/** A snapshot is a state with no start, so the API refuses to reset it (422). */
export function isResettable(key: string) {
  const metric = STAFF_METRICS[key];
  return Boolean(metric) && metric.kind !== "snapshot";
}

/** Metrics where a fall is the good news. */
export const LOWER_IS_BETTER = new Set([
  "overview.churn_rate",
  "overview.members_at_risk",
  "training.no_show_rate",
  "training.late_cancellations",
  "health.injuries_per_1000_attendances",
  "health.mean_recovery_days",
  "finance.days_sales_outstanding",
]);

export type DeltaTone = "good" | "bad" | "flat" | "none";

export function deltaTone(key: string, delta: number | null | undefined): DeltaTone {
  if (typeof delta !== "number" || !Number.isFinite(delta)) return "none";
  if (delta === 0) return "flat";
  const up = delta > 0;
  return up !== LOWER_IS_BETTER.has(key) ? "good" : "bad";
}

export const DELTA_COLOR: Record<DeltaTone, string> = {
  good: "var(--success)",
  bad: "var(--danger)",
  flat: "var(--muted)",
  none: "var(--muted)",
};

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

function num(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function rows(value: unknown): KpiRow[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const row = record(item);
    if (Object.keys(row).length === 0) return [];
    const key = typeof row.key === "string" || typeof row.key === "number" ? row.key : null;
    return [{ ...row, key, suppressed: row.suppressed === true }];
  });
}

/** One KPI from the payload; unknown fields fall back to «no data». */
export function readKpi(payload: unknown, key: string): Kpi {
  const entry = record(record(record(payload).kpis)[key]);
  const known = STAFF_METRICS[key];
  const unit = (typeof entry.unit === "string" ? entry.unit : known?.unit ?? "count") as KpiUnit;
  const kind = (typeof entry.kind === "string" ? entry.kind : known?.kind ?? "flow") as KpiKind;
  const suppressed = entry.suppressed === true;
  return {
    key,
    unit,
    kind,
    value: suppressed ? null : num(entry.value),
    previous: num(entry.previous),
    delta: suppressed ? null : num(entry.delta),
    since: typeof entry.since === "string" && entry.since ? entry.since : null,
    suppressed,
    previousSuppressed: entry.previous_suppressed === true,
    rows: suppressed ? [] : rows(entry.rows),
  };
}

/** The keys of the payload's KPIs that this page knows how to show, in registry order. */
export function kpiKeys(payload: unknown): string[] {
  const present = new Set(Object.keys(record(record(payload).kpis)));
  return Object.keys(STAFF_METRICS).filter((key) => present.has(key));
}

export function rowNumber(row: KpiRow, field: string): number | null {
  return num(row[field]);
}
