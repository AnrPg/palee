"use client";

import { useTranslations } from "next-intl";
import { useState, type CSSProperties } from "react";

import { DateInput } from "@/components/ui/DateInput";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import {
  ANALYTICS_PERIODS,
  FIXED_DIMENSION_VALUES,
  activeFilterCount,
  analyticsRange,
  clearDimensions,
  type AnalyticsDimension,
  type AnalyticsFilter,
  type AnalyticsPeriod,
} from "@/lib/analytics-filter";

import { MetricHelp } from "./MetricHelp";
import { useAnalyticsDirectory, type AnalyticsDirectory, type DirectoryOption } from "./use-analytics-directory";

const DEMOGRAPHIC: readonly AnalyticsDimension[] = ["age_bands", "genders"];

function chipStyle(on: boolean): CSSProperties {
  return on
    ? { background: "color-mix(in srgb, var(--primary) 16%, var(--panel))", border: "1px solid var(--primary)", color: "var(--text)" }
    : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" };
}

/** The options of one dimension: fixed lists are labelled from messages, the rest come from the box. */
export function useDimensionOptions(directory: AnalyticsDirectory) {
  const t = useTranslations("StaffAnalytics");
  return (dimension: AnalyticsDimension): DirectoryOption[] => {
    const fixed = FIXED_DIMENSION_VALUES[dimension];
    if (fixed) return fixed.map((value) => ({ value, label: t(`values.${dimension}.${value}`) }));
    if (dimension === "location_ids") return directory.locations.length >= 2 ? directory.locations : [];
    if (dimension === "class_type_ids") return directory.classTypes;
    if (dimension === "coach_ids") return directory.coaches;
    if (dimension === "package_ids") return directory.packages;
    return [];
  };
}

/**
 * ADR-462 (ANR, mockup 2026-11-04 tab 4 option A): the period bar that is
 * always in view, «σε σύγκριση με τις προηγούμενες N», one «Φίλτρα (N) ▾»
 * that opens a sheet with the page's chip groups, and the filters in force
 * as removable chips under the bar. The same filter applies to the whole
 * page. On a phone the period bar scrolls inside itself, never the page.
 */
export function AnalyticsFilterBar({
  filter,
  onChange,
  dimensions,
  days,
  today,
  page,
}: {
  filter: AnalyticsFilter;
  onChange: (filter: AnalyticsFilter) => void;
  /** The dimensions that narrow this page's figures. */
  dimensions: readonly AnalyticsDimension[];
  days: number;
  today: string;
  /** The page key of the page-level infobox (`pages.<page>`). */
  page: string;
}) {
  const t = useTranslations("StaffAnalytics");
  const directory = useAnalyticsDirectory();
  const options = useDimensionOptions(directory);
  const [sheetOpen, setSheetOpen] = useState(false);
  const shown = dimensions.filter((dimension) => options(dimension).length > 0 || filter[dimension].length > 0);
  const count = activeFilterCount(filter, shown);

  const pickPeriod = (period: AnalyticsPeriod) => {
    if (period === "custom") {
      const range = analyticsRange(filter, today);
      onChange({ ...filter, period, from: filter.from ?? range.from, to: filter.to ?? range.to });
    } else {
      onChange({ ...filter, period, from: null, to: null });
    }
  };

  const labelOf = (dimension: AnalyticsDimension, value: string) =>
    options(dimension).find((option) => option.value === value)?.label ?? t("filters.unknownValue");

  const remove = (dimension: AnalyticsDimension, value: string) =>
    onChange({ ...filter, [dimension]: filter[dimension].filter((item) => item !== value) });

  return (
    <section aria-label={t("filters.region")} className="space-y-3" data-testid="analytics-filter-bar">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        <div className="min-w-0 max-w-full overflow-x-auto [scrollbar-width:none]">
          <div
            role="group"
            aria-label={t("period.label")}
            className="flex w-max gap-0.5 rounded-full p-1"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            {ANALYTICS_PERIODS.map((period) => {
              const on = filter.period === period;
              return (
                <button
                  key={period}
                  type="button"
                  aria-pressed={on}
                  onClick={() => pickPeriod(period)}
                  className="min-h-9 whitespace-nowrap rounded-full px-3 text-sm font-semibold"
                  style={
                    on
                      ? { background: "var(--panel)", color: "var(--text)", boxShadow: "0 1px 3px color-mix(in srgb, var(--text) 18%, transparent)" }
                      : { background: "transparent", color: "var(--muted)" }
                  }
                >
                  {t(`period.options.${period}`)}
                </button>
              );
            })}
          </div>
        </div>
        <button
          type="button"
          onClick={() => setSheetOpen(true)}
          aria-haspopup="dialog"
          aria-expanded={sheetOpen}
          className="inline-flex min-h-10 shrink-0 items-center gap-1.5 rounded-full px-4 text-sm font-semibold"
          style={chipStyle(count > 0)}
          data-testid="analytics-filters-button"
        >
          {t("filters.button", { count })}
          <span aria-hidden="true" className="text-xs" style={{ color: "var(--dim)" }}>▾</span>
        </button>
        <span className="flex min-w-0 items-center gap-1.5 text-sm" style={{ color: "var(--muted)" }}>
          <span className="min-w-0">{t("period.compare", { count: days })}</span>
          <MetricHelp label={t(`pages.${page}.title`)} path={`pages.${page}`} />
        </span>
      </div>

      {filter.period === "custom" ? (
        <div className="grid max-w-md grid-cols-2 gap-2">
          <label className="flex min-w-0 flex-col gap-1 text-xs font-semibold" style={{ color: "var(--muted)" }}>
            {t("period.from")}
            <DateInput
              value={filter.from ?? ""}
              max={filter.to ?? today}
              onValueChange={(value) => onChange({ ...filter, from: value || null })}
              className="min-h-10 w-full rounded-xl px-3 text-sm"
              aria-label={t("period.from")}
            />
          </label>
          <label className="flex min-w-0 flex-col gap-1 text-xs font-semibold" style={{ color: "var(--muted)" }}>
            {t("period.to")}
            <DateInput
              value={filter.to ?? ""}
              min={filter.from ?? undefined}
              max={today}
              onValueChange={(value) => onChange({ ...filter, to: value || null })}
              className="min-h-10 w-full rounded-xl px-3 text-sm"
              aria-label={t("period.to")}
            />
          </label>
        </div>
      ) : null}

      {count > 0 ? (
        <ul aria-label={t("filters.active")} className="flex flex-wrap gap-2">
          {shown.flatMap((dimension) =>
            filter[dimension].map((value) => {
              const text = t("filters.chip", { group: t(`groups.${dimension}`), value: labelOf(dimension, value) });
              return (
                <li key={`${dimension}:${value}`} className="min-w-0 max-w-full">
                  <button
                    type="button"
                    onClick={() => remove(dimension, value)}
                    aria-label={t("filters.remove", { label: text })}
                    className="inline-flex min-h-9 max-w-full items-center gap-1.5 rounded-full px-3 text-sm font-semibold"
                    style={chipStyle(true)}
                  >
                    <span className="truncate">{text}</span>
                    <span aria-hidden="true" style={{ color: "var(--primary-strong)" }}>✕</span>
                  </button>
                </li>
              );
            }),
          )}
        </ul>
      ) : null}

      {sheetOpen ? (
        <FilterSheet
          filter={filter}
          onChange={onChange}
          dimensions={shown}
          options={options}
          onClose={() => setSheetOpen(false)}
          count={count}
        />
      ) : null}
    </section>
  );
}

function FilterSheet({
  filter,
  onChange,
  dimensions,
  options,
  onClose,
  count,
}: {
  filter: AnalyticsFilter;
  onChange: (filter: AnalyticsFilter) => void;
  dimensions: readonly AnalyticsDimension[];
  options: (dimension: AnalyticsDimension) => DirectoryOption[];
  onClose: () => void;
  count: number;
}) {
  const t = useTranslations("StaffAnalytics");
  const toggle = (dimension: AnalyticsDimension, value: string) => {
    const current = filter[dimension];
    onChange({ ...filter, [dimension]: current.includes(value) ? current.filter((item) => item !== value) : [...current, value] });
  };
  const hasDemographics = dimensions.some((dimension) => DEMOGRAPHIC.includes(dimension));

  return (
    <Dialog
      onClose={onClose}
      title={t("filters.title")}
      size="lg"
      variant="sheet"
      testId="analytics-filter-sheet"
      footerStart={
        count > 0 ? (
          <DialogButton tone="ghost" onClick={() => onChange(clearDimensions(filter))}>
            {t("filters.clear")}
          </DialogButton>
        ) : null
      }
      footer={
        <DialogButton tone="primary" onClick={onClose}>
          {t("filters.done")}
        </DialogButton>
      }
    >
      <div className="space-y-5">
        {dimensions.map((dimension) => {
          const selected = filter[dimension];
          const choices = options(dimension);
          return (
            <fieldset key={dimension} className="min-w-0">
              <legend className="mb-2 text-sm font-bold" style={{ color: "var(--text)" }}>
                {t(`groups.${dimension}`)}
                {DEMOGRAPHIC.includes(dimension) ? <span aria-hidden="true"> *</span> : null}
              </legend>
              <div className="flex flex-wrap gap-2">
                <button
                  type="button"
                  aria-pressed={selected.length === 0}
                  onClick={() => onChange({ ...filter, [dimension]: [] })}
                  className="min-h-9 rounded-full px-3.5 text-sm font-semibold"
                  style={chipStyle(selected.length === 0)}
                >
                  {t("filters.all")}
                </button>
                {choices.map((option) => {
                  const on = selected.includes(option.value);
                  return (
                    <button
                      key={option.value}
                      type="button"
                      aria-pressed={on}
                      onClick={() => toggle(dimension, option.value)}
                      className="min-h-9 max-w-full truncate rounded-full px-3.5 text-sm font-semibold"
                      style={chipStyle(on)}
                    >
                      {option.label}
                    </button>
                  );
                })}
              </div>
            </fieldset>
          );
        })}
        {hasDemographics ? (
          <p className="text-xs leading-5" style={{ color: "var(--muted)" }}>
            {t("filters.demographicsNote")}
          </p>
        ) : null}
      </div>
    </Dialog>
  );
}
