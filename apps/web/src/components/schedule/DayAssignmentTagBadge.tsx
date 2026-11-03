"use client";

import { useTranslations } from "next-intl";

import type { DayAssignmentTag } from "@/api/day-workouts";
import { dayTagView } from "@/lib/training-floor";

const TONES = {
  success: "var(--success)",
  warning: "var(--warning)",
  danger: "var(--danger)",
  muted: "var(--muted)",
} as const;

/**
 * ADR-357 (ANR mockup d3 A): a word tag on each programming day, never colour
 * alone. «Μερικά με WOD · 1/3» says how many classes have their WOD. A day
 * without classes is plain muted text.
 */
export function DayAssignmentTagBadge({ day, compact = false }: { day: DayAssignmentTag; compact?: boolean }) {
  const t = useTranslations("TrainingFloor");
  const view = dayTagView(day.tag);
  const label = t(view.key, { withWod: day.with_wod, classes: day.classes });
  const color = TONES[view.tone];

  if (view.tone === "muted") {
    return (
      <span className={compact ? "block truncate text-[9px]" : "mt-2 block text-[11px]"} style={{ color }} data-testid={`day-tag-${day.date}`}>
        {label}
      </span>
    );
  }

  return (
    <span
      className={
        compact
          ? "mt-0.5 block w-full truncate rounded px-1 text-[9px] font-bold"
          : "mt-2 inline-block max-w-full truncate rounded-full px-2 py-0.5 text-[11px] font-bold"
      }
      style={{ background: `color-mix(in srgb, ${color} 14%, transparent)`, color }}
      data-testid={`day-tag-${day.date}`}
    >
      {label}
    </span>
  );
}
