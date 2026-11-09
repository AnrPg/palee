"use client";

import type { CSSProperties } from "react";

import { Select } from "@/components/ui/Select";
import { useUiTranslations } from "@/i18n/ui";
import {
  FREE_TEXT_TIMER_FORMATS,
  type FreeTextTimerFormat,
  type FreeTextTimerPreset,
  NO_TIME_PRESET,
  sameTimerPreset,
  timerChipLabel,
} from "@/lib/free-text-timer";
import type { SectionFormat } from "@/types/workout";

import { FreeTextTimerFields } from "./FreeTextTimerFields";

type Props = {
  preset: FreeTextTimerPreset;
  /** The coach's most used timers (ADR-571), most used first; never «Χωρίς χρόνο». */
  frequent: FreeTextTimerPreset[];
  formatLabels: Record<SectionFormat, string>;
  onChange: (preset: FreeTextTimerPreset) => void;
};

const chipStyle = (active: boolean): CSSProperties =>
  active
    ? {
        background: "var(--primary)",
        color: "var(--primary-contrast)",
        border: "1px solid var(--primary)",
      }
    : { border: "1px solid var(--border)", color: "var(--text-soft)" };

/**
 * ADR-571: a text section's timer. Three chips with the coach's most used
 * timers, «Χωρίς χρόνο» (the default), and a dropdown with every format; the
 * numbers of the chosen format follow underneath.
 */
export function TimerChips({ preset, frequent, formatLabels, onChange }: Props) {
  const i18n = useUiTranslations();
  const labels = { ...formatLabels, untimed: i18n("timerNoTime") };
  const noTime = preset.format === "untimed";
  const fromChip = noTime || frequent.some((chip) => sameTimerPreset(chip, preset));

  return (
    <>
      <div className="flex flex-wrap items-center gap-2" role="group" aria-label={i18n("timerPresetsLabel")}>
        {frequent.map((chip) => {
          const active = sameTimerPreset(chip, preset);
          return (
            <button
              key={JSON.stringify(chip)}
              type="button"
              aria-pressed={active}
              data-testid="timer-chip"
              onClick={() => onChange(chip)}
              className="min-h-9 rounded-full px-3 text-xs font-semibold tabular-nums"
              style={chipStyle(active)}
            >
              {timerChipLabel(chip, labels[chip.format])}
            </button>
          );
        })}
        <button
          type="button"
          aria-pressed={noTime}
          data-testid="timer-chip-no-time"
          onClick={() => onChange(NO_TIME_PRESET)}
          className="min-h-9 rounded-full px-3 text-xs font-semibold"
          style={chipStyle(noTime)}
        >
          {labels.untimed}
        </button>
        <Select
          value={preset.format}
          onValueChange={(value) => onChange({ format: value as FreeTextTimerFormat })}
          aria-label={i18n("timerFormatLabel")}
          data-testid="timer-format-select"
          className="min-h-9 rounded-full px-3 text-xs font-bold"
          style={
            {
              // Deep, not Dojo like the chips: the dropdown reads as the menu of
              // every format; a format picked here (no chip) gets the Dojo ring.
              background: "var(--deep)",
              color: "var(--deep-contrast)",
              border: `2px solid ${fromChip ? "var(--deep)" : "var(--primary)"}`,
              "--select-chevron": "var(--deep-contrast)",
            } as CSSProperties
          }
        >
          {FREE_TEXT_TIMER_FORMATS.map((item) => (
            <option key={item} value={item}>
              {labels[item]}
            </option>
          ))}
        </Select>
      </div>
      <FreeTextTimerFields preset={preset} formatLabels={labels} onChange={onChange} showFormat={false} />
    </>
  );
}
