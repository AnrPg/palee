"use client";

import { useTranslations } from "next-intl";
import { useCallback } from "react";

import { ApiError } from "@/api/client";
import type { ProgrammeGoal, ProgrammeLevel } from "@/api/programmes";
import { useUiTranslations } from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { formatMinorUnits } from "@/lib/finance-accounting";

/** The API's programme refusals in plain words; anything else in the app's general wording. */
const PROGRAMME_CODES = new Set([
  "invalid_programme_days",
  "programme_price_required",
  "programme_workout_unavailable",
  "programme_archived",
  "programme_not_for_sale",
  "programme_already_owned",
  "invalid_start_date",
  "programme_start_consent_required",
  "programme_refund_not_available",
  "refund_exceeds_remaining",
  "review_too_early",
  "review_not_allowed",
  "invalid_review",
  "online_payments_unavailable",
]);

/** The day refusals of a bought programme (ADR-540): «Κάν' τη σήμερα» and «Παράλειψη». */
export const PROGRAMME_DAY_CODES = [
  "programme_day_not_behind",
  "programme_day_not_found",
  "programme_schedule_limit",
  "programme_purchase_not_active",
] as const;
type ProgrammeDayCode = (typeof PROGRAMME_DAY_CODES)[number];

export function programmeErrorKey(error: unknown): string | null {
  if (!(error instanceof ApiError)) return null;
  const code = error.payload.code;
  return typeof code === "string" && PROGRAMME_CODES.has(code) ? code : null;
}

export function programmeDayErrorKey(error: unknown): ProgrammeDayCode | null {
  if (!(error instanceof ApiError)) return null;
  const code = error.payload?.code;
  return (PROGRAMME_DAY_CODES as readonly unknown[]).includes(code) ? (code as ProgrammeDayCode) : null;
}

export function useProgrammeError() {
  const t = useTranslations("Programmes");
  const ui = useUiTranslations();
  return useCallback(
    (error: unknown) => {
      const key = programmeErrorKey(error);
      if (key) return t(`errors.${key}`);
      const day = programmeDayErrorKey(error);
      return day ? t(`buyer2.errors.${day}`) : localizeError(error, ui);
    },
    [t, ui],
  );
}

export function programmeMoney(locale: string, cents: number | null | undefined, currency?: string | null) {
  return formatMinorUnits(locale, cents ?? 0, currency || "EUR");
}

export const LEVEL_KEYS: Record<string, string> = {
  all: "level.all",
  beginner: "level.beginner",
  intermediate: "level.intermediate",
  advanced: "level.advanced",
};

export function useProgrammeLabels() {
  const t = useTranslations("Programmes");
  return {
    level: (level?: ProgrammeLevel | string | null) => (level && LEVEL_KEYS[level] ? t(LEVEL_KEYS[level]) : ""),
    goal: (goal?: ProgrammeGoal | string | null) =>
      goal && (GOALS as readonly string[]).includes(goal) ? t(`goal.${goal}` as `goal.${(typeof GOALS)[number]}`) : "",
  };
}

export const GOALS = [
  "general",
  "strength",
  "conditioning",
  "gymnastics",
  "weightlifting",
  "endurance",
  "competition",
  "hyrox",
  "mobility",
] as const;

export const LEVELS = ["all", "beginner", "intermediate", "advanced"] as const;

/** «★ 4,8 (23)», or nothing without reviews. */
export function ratingLabel(locale: string, average: number | null | undefined, count: number | null | undefined) {
  const stars = ratingStars(locale, average, count);
  return stars ? `${stars} (${count})` : null;
}

/** «★ 4,8», or nothing without reviews. */
export function ratingStars(locale: string, average: number | null | undefined, count: number | null | undefined) {
  if (!count || typeof average !== "number" || !Number.isFinite(average)) return null;
  return `★ ${new Intl.NumberFormat(locale, { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(average)}`;
}
