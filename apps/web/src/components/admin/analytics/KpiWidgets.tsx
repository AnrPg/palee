"use client";

import { useTranslations } from "next-intl";
import type { ReactNode } from "react";

import { SemanticLabel } from "@/components/semantic-label";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { DELTA_COLOR, deltaTone, rowNumber, type Kpi, type KpiRow, type KpiUnit } from "@/lib/analytics-kpi";
import { useOrganizationTimeZone } from "@/lib/organization-slug";
import { dateKeyInZone } from "@/lib/zoned-time";

import { MetricHelp, type HelpContent } from "./MetricHelp";
import type { AnalyticsDirectory } from "./use-analytics-directory";

/** The registry key as a message path: `metrics.training.no_show_rate`. */
export const metricPath = (key: string) => `metrics.${key}`;

export function useKpiFormat() {
  const locale = useUiLocale();
  const t = useTranslations("StaffAnalytics");
  const decimal = (value: number, digits = 1, sign = false) =>
    new Intl.NumberFormat(locale, { maximumFractionDigits: digits, signDisplay: sign ? "exceptZero" : "auto" }).format(value);

  const value = (unit: KpiUnit, amount: number) => {
    switch (unit) {
      case "percent":
        return new Intl.NumberFormat(locale, { style: "percent", maximumFractionDigits: 1 }).format(amount / 100);
      case "cents":
        return new Intl.NumberFormat(locale, { style: "currency", currency: "EUR", maximumFractionDigits: 0 }).format(amount / 100);
      case "days":
        return t("kpi.days", { count: Math.round(amount * 10) / 10 });
      case "count":
        return decimal(amount, 1);
      default:
        return decimal(amount, 2);
    }
  };

  const delta = (unit: KpiUnit, amount: number) => {
    switch (unit) {
      case "percent":
        return t("kpi.points", { value: decimal(amount, 1, true) });
      case "cents":
        return new Intl.NumberFormat(locale, { style: "currency", currency: "EUR", maximumFractionDigits: 0, signDisplay: "exceptZero" }).format(amount / 100);
      case "days":
        return t("kpi.daysChange", { sign: amount > 0 ? "+" : "−", count: Math.round(Math.abs(amount) * 10) / 10 });
      default:
        return decimal(amount, 2, true);
    }
  };

  return { value, delta, decimal };
}

/** «από 4 Νοε»: the active reset baseline, as the gym's calendar day. */
export function useSinceLabel() {
  const t = useTranslations("StaffAnalytics");
  const locale = useUiLocale();
  const zone = useOrganizationTimeZone();
  return (since: string | null) => {
    if (!since || Number.isNaN(Date.parse(since))) return null;
    const day = dateKeyInZone(since, zone);
    const date = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", timeZone: "UTC" }).format(new Date(`${day}T12:00:00Z`));
    return t("kpi.since", { date });
  };
}

/** A widget's title line: the label (truncating), the reset date inline, and the «?». */
function WidgetLabel({
  label,
  since,
  help,
  as = "p",
}: {
  label: string;
  since: string | null;
  help: ReactNode;
  as?: "p" | "h3";
}) {
  const sinceLabel = useSinceLabel()(since);
  const Tag = as;
  return (
    <div className="flex min-w-0 items-center gap-1.5">
      <Tag
        className={
          as === "h3"
            ? "min-w-0 truncate text-base font-black"
            : "min-w-0 truncate text-xs font-bold uppercase tracking-[0.14em]"
        }
        style={{ color: as === "h3" ? "var(--text)" : "var(--muted)" }}
        title={sinceLabel ? `${label} · ${sinceLabel}` : label}
      >
        {label}
        {sinceLabel ? (
          <span className="ms-1.5 text-[11px] font-semibold normal-case tracking-normal" style={{ color: "var(--dim)" }} data-testid="metric-since">
            {sinceLabel}
          </span>
        ) : null}
      </Tag>
      {help}
    </div>
  );
}

/** «+1,2 μον.» in green or red (red when the change is the bad kind), or why there is none. */
export function KpiDelta({ kpi }: { kpi: Kpi }) {
  const t = useTranslations("StaffAnalytics");
  const format = useKpiFormat();
  if (kpi.suppressed) return <span style={{ color: "var(--muted)" }}>{t("kpi.suppressedReason")}</span>;
  if (kpi.delta === null) return <span style={{ color: "var(--muted)" }}>{t("kpi.noPrevious")}</span>;
  const tone = deltaTone(kpi.key, kpi.delta);
  return (
    <span data-tone={tone} style={{ color: DELTA_COLOR[tone] }}>
      {kpi.delta === 0 ? t("kpi.unchanged") : format.delta(kpi.unit, kpi.delta)}
      {kpi.previous !== null ? (
        <span className="ms-1" style={{ color: "var(--muted)" }}>
          {t("kpi.previous", { value: format.value(kpi.unit, kpi.previous) })}
        </span>
      ) : null}
    </span>
  );
}

export function KpiValue({ kpi }: { kpi: Kpi }) {
  const t = useTranslations("StaffAnalytics");
  const format = useKpiFormat();
  if (kpi.suppressed) return <span aria-label={t("kpi.suppressedReason")}>{t("kpi.suppressed")}</span>;
  if (kpi.value === null) return <span aria-label={t("kpi.noValue")}>{t("kpi.suppressed")}</span>;
  return <>{format.value(kpi.unit, kpi.value)}</>;
}

/** One KPI: value, change against the previous period, and its own infobox. */
export function KpiTile({ kpi }: { kpi: Kpi }) {
  const t = useTranslations("StaffAnalytics");
  const label = t(`${metricPath(kpi.key)}.label`);
  return (
    <article
      className="min-w-0 rounded-2xl p-4"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid={`kpi-${kpi.key}`}
    >
      <WidgetLabel label={label} since={kpi.since} help={<MetricHelp label={label} path={metricPath(kpi.key)} metricKey={kpi.key} />} />
      <p className="mt-2 text-2xl font-black tabular-nums" style={{ color: "var(--text)" }}>
        <KpiValue kpi={kpi} />
      </p>
      <p className="mt-1 text-xs tabular-nums">
        <KpiDelta kpi={kpi} />
      </p>
    </article>
  );
}

/** A plain tile for a figure outside the metric registry (it has no delta and no reset). */
export function PlainTile({ label, value, detail, helpPath, content }: { label: string; value: string; detail?: string; helpPath?: string; content?: HelpContent }) {
  return (
    <article className="min-w-0 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <WidgetLabel label={label} since={null} help={<MetricHelp label={label} path={helpPath} content={content} />} />
      <p className="mt-2 text-2xl font-black tabular-nums" style={{ color: "var(--text)" }}>{value}</p>
      {detail ? <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>{detail}</p> : null}
    </article>
  );
}

/** A card with a title line and its own infobox; the body is the caller's. */
export function WidgetCard({
  label,
  since = null,
  helpPath,
  content,
  metricKey,
  aside,
  children,
  testId,
}: {
  label: string;
  since?: string | null;
  helpPath?: string;
  content?: HelpContent;
  metricKey?: string;
  aside?: ReactNode;
  children: ReactNode;
  testId?: string;
}) {
  return (
    <article className="min-w-0 rounded-[1.6rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid={testId}>
      <div className="mb-4 flex min-w-0 items-start justify-between gap-3">
        <WidgetLabel as="h3" label={label} since={since} help={<MetricHelp label={label} path={helpPath} content={content} metricKey={metricKey} />} />
        {aside}
      </div>
      {children}
    </article>
  );
}

export type BarRow = { id: string; label: ReactNode; value: number | null; text: string; suppressed?: boolean };

export function EmptyFacts() {
  const t = useTranslations("StaffAnalytics");
  return <p className="text-sm" style={{ color: "var(--muted)" }}>{t("kpi.noData")}</p>;
}

/** A labelled horizontal bar per row; a suppressed row shows «—» and no bar. */
export function BarList({ rows }: { rows: BarRow[] }) {
  const t = useTranslations("StaffAnalytics");
  if (rows.length === 0) return <EmptyFacts />;
  const max = Math.max(1, ...rows.map((row) => row.value ?? 0));
  return (
    <ul className="space-y-3">
      {rows.map((row) => {
        const width = row.value && row.value > 0 ? Math.max((row.value / max) * 100, 4) : 0;
        return (
          <li key={row.id}>
            <div className="flex min-w-0 items-center justify-between gap-3 text-sm">
              <span className="min-w-0 truncate" style={{ color: "var(--text-soft)" }}>{row.label}</span>
              <span className="shrink-0 font-bold tabular-nums" style={{ color: "var(--text)" }}>
                {row.suppressed ? <span title={t("kpi.suppressedReason")}>{t("kpi.suppressed")}</span> : row.text}
              </span>
            </div>
            <div className="mt-1.5 h-2 rounded-full" style={{ background: "var(--panel-muted)" }}>
              {width > 0 ? <div className="h-2 rounded-full" style={{ width: `${width}%`, background: "var(--primary)" }} /> : null}
            </div>
          </li>
        );
      })}
    </ul>
  );
}

/** Columns for an ordered breakdown (hours, weekdays), each with its value in its name. */
export function ColumnChart({ rows, ariaLabel }: { rows: BarRow[]; ariaLabel: string }) {
  if (rows.length === 0) return <EmptyFacts />;
  const max = Math.max(1, ...rows.map((row) => row.value ?? 0));
  return (
    <ol aria-label={ariaLabel} className="flex h-36 items-end gap-1">
      {rows.map((row) => (
        <li key={row.id} className="flex h-full min-w-0 flex-1 flex-col items-center justify-end gap-1" aria-label={`${typeof row.label === "string" ? row.label : row.id}: ${row.text}`}>
          <span aria-hidden="true" className="text-[10px] tabular-nums" style={{ color: "var(--dim)" }}>{row.suppressed ? "—" : row.text}</span>
          <span
            aria-hidden="true"
            className="w-full rounded-t-md"
            style={{ height: `${row.value ? Math.max((row.value / max) * 100, 3) : 0}%`, background: "var(--primary)" }}
          />
          <span aria-hidden="true" className="max-w-full truncate text-[10px] tabular-nums" style={{ color: "var(--muted)" }}>{row.label}</span>
        </li>
      ))}
    </ol>
  );
}

/**
 * The rows of a breakdown metric as bars, with the labels and numbers each
 * one needs (coach names, weekdays, package names, opt-in buckets).
 */
export function useBreakdownRows(directory: AnalyticsDirectory) {
  const t = useTranslations("StaffAnalytics");
  const locale = useUiLocale();
  const format = useKpiFormat();
  const count = (value: number) => format.decimal(value, 0);

  const coach = (row: KpiRow) =>
    (typeof row.key === "string" && directory.staffName.get(row.key)) || t("kpi.unknownCoach");

  return (kpi: Kpi): BarRow[] => {
    const id = (row: KpiRow, index: number) => String(row.key ?? index);
    switch (kpi.key) {
      case "training.attendance_by_hour":
        return kpi.rows
          .filter((row) => typeof row.key === "number")
          .sort((a, b) => Number(a.key) - Number(b.key))
          .map((row, index) => ({
            id: id(row, index),
            label: `${String(row.key).padStart(2, "0")}:00`,
            value: rowNumber(row, "count"),
            text: count(rowNumber(row, "count") ?? 0),
            suppressed: row.suppressed,
          }));
      case "training.attendance_by_weekday": {
        const weekday = new Intl.DateTimeFormat(locale, { weekday: "short", timeZone: "UTC" });
        return [1, 2, 3, 4, 5, 6, 7].map((day) => {
          const row = kpi.rows.find((item) => Number(item.key) === day);
          const value = row ? rowNumber(row, "count") ?? 0 : 0;
          return {
            id: String(day),
            // 2024-01-01 was a Monday (ISO weekday 1).
            label: weekday.format(new Date(Date.UTC(2024, 0, day))),
            value,
            text: count(value),
            suppressed: row?.suppressed,
          };
        });
      }
      case "coaching.classes_per_coach":
        return kpi.rows.map((row, index) => ({
          id: id(row, index),
          label: coach(row),
          value: rowNumber(row, "attendances"),
          text: t("kpi.classesAttendances", { classes: rowNumber(row, "classes") ?? 0, attendances: rowNumber(row, "attendances") ?? 0 }),
          suppressed: row.suppressed,
        }));
      case "coaching.athletes_per_coach":
        return kpi.rows.map((row, index) => ({
          id: id(row, index),
          label: coach(row),
          value: rowNumber(row, "athletes"),
          text: t("kpi.athletes", { count: rowNumber(row, "athletes") ?? 0 }),
          suppressed: row.suppressed,
        }));
      case "coaching.review_rating_per_coach":
        return kpi.rows.map((row, index) => ({
          id: id(row, index),
          label: coach(row),
          value: rowNumber(row, "rating"),
          text: t("kpi.rating", { rating: format.decimal(rowNumber(row, "rating") ?? 0, 1), count: rowNumber(row, "count") ?? 0 }),
          suppressed: row.suppressed,
        }));
      case "health.top_body_areas":
        return kpi.rows.map((row, index) => ({
          id: id(row, index),
          label: <SemanticLabel value={row.key} />,
          value: rowNumber(row, "count"),
          text: count(rowNumber(row, "count") ?? 0),
          suppressed: row.suppressed,
        }));
      case "finance.revenue_per_package":
        return kpi.rows.map((row, index) => ({
          id: id(row, index),
          label:
            row.key === "none"
              ? t("kpi.noPackage")
              : (typeof row.key === "string" && directory.packageNameByCode.get(row.key)) || String(row.key ?? ""),
          value: rowNumber(row, "cents"),
          text: format.value("cents", rowNumber(row, "cents") ?? 0),
          suppressed: row.suppressed,
        }));
      case "demographics.age_bands":
      case "demographics.genders": {
        const dimension = kpi.key === "demographics.age_bands" ? "age_bands" : "genders";
        return kpi.rows.map((row, index) => ({
          id: id(row, index),
          label: t.has(`values.${dimension}.${row.key}`) ? t(`values.${dimension}.${row.key}`) : String(row.key ?? ""),
          value: rowNumber(row, "people"),
          text: t("kpi.people", { count: rowNumber(row, "people") ?? 0 }),
          suppressed: row.suppressed,
        }));
      }
      default:
        return kpi.rows.map((row, index) => ({
          id: id(row, index),
          label: <SemanticLabel value={row.key} />,
          value: rowNumber(row, "count"),
          text: count(rowNumber(row, "count") ?? 0),
          suppressed: row.suppressed,
        }));
    }
  };
}

/**
 * A breakdown metric in one card: its headline figure (when it has one,
 * e.g. the average rating) with the change, then its rows.
 */
export function BreakdownCard({ kpi, directory, headline = false, chart = "bars" }: { kpi: Kpi; directory: AnalyticsDirectory; headline?: boolean; chart?: "bars" | "columns" }) {
  const t = useTranslations("StaffAnalytics");
  const rowsOf = useBreakdownRows(directory);
  const label = t(`${metricPath(kpi.key)}.label`);
  const rows = rowsOf(kpi);
  return (
    <WidgetCard label={label} since={kpi.since} helpPath={metricPath(kpi.key)} metricKey={kpi.key} testId={`kpi-${kpi.key}`}>
      {headline ? (
        <div className="mb-4">
          <p className="text-2xl font-black tabular-nums" style={{ color: "var(--text)" }}>
            <KpiValue kpi={kpi} />
          </p>
          <p className="mt-1 text-xs tabular-nums">
            <KpiDelta kpi={kpi} />
          </p>
        </div>
      ) : null}
      {kpi.suppressed ? (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("kpi.suppressedReason")}</p>
      ) : chart === "columns" ? (
        <ColumnChart rows={rows} ariaLabel={label} />
      ) : (
        <BarList rows={rows} />
      )}
    </WidgetCard>
  );
}
