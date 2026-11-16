"use client";

import { useTranslations } from "next-intl";
import type { ReactNode } from "react";

import { timerChipLabel, type FreeTextTimerPreset } from "@/lib/free-text-timer";
import type { TextTimers } from "@/lib/wod-formats/parse";
import { pickedTextTimer, type TimerFrom } from "@/lib/wod-formats/text-timer";
import type { SectionFormat } from "@/types/workout";

type Props = {
  /** The timer the WOD runs now. */
  preset: FreeTextTimerPreset | null;
  source: TimerFrom;
  found: TextTimers;
  formatLabels: Record<SectionFormat, string>;
  /** The free-text editor has one timer: two found get the «split into sections» note. */
  oneTimer: boolean;
  /** Opens the timer fields («Αλλαγή»); none where the fields are already shown. */
  onChange?: () => void;
  onRestore: () => void;
  onNext: () => void;
  /** False where the timer button itself already shows the timer (text sections). */
  showChip?: boolean;
  /** «Πώς γράφω το χρονόμετρο;», shown whenever the note is. */
  help?: ReactNode;
};

/**
 * ADR-650: the timer a text WOD got from its words. Green «από το κείμενο»
 * while it follows the text, the coach's own after a change by hand (with
 * «Από το κείμενο» when the text asks for a timer). Several found: «βρέθηκαν
 * 2» and «Το επόμενο». A format missing its number: how to complete it.
 * Shows nothing when the text says nothing about a timer.
 */
export function TextTimerNote({ preset, source, found, formatLabels, oneTimer, onChange, onRestore, onNext, showChip = true, help }: Props) {
  const t = useTranslations("TextTimer");
  const fromText = source.from === "text" && preset !== null && found.timers.length > 0;
  const textHasTimer = found.timers.length > 0;
  const missing = !textHasTimer && found.incomplete[0] ? found.incomplete[0] : null;
  const several = fromText && found.timers.length > 1;
  if (!(fromText && showChip) && !several && !(source.from === "hand" && textHasTimer) && !missing) return null;

  const label = (value: FreeTextTimerPreset) => timerChipLabel(value, formatLabels[value.format]);
  const picked = pickedTextTimer(found, source.pick);

  return (
    <div className="flex flex-col gap-1.5 text-xs" data-testid="text-timer-note" aria-live="polite">
      <div className="flex flex-wrap items-center gap-2">
        {fromText && preset && showChip ? (
          <span
            className="inline-flex min-h-8 items-center gap-1.5 rounded-full px-3 font-bold tabular-nums"
            style={{
              background: "color-mix(in srgb, var(--success) 14%, var(--card))",
              border: "1px solid var(--success)",
              color: "var(--success)",
            }}
            data-testid="text-timer-chip"
          >
            <span aria-hidden="true">⏱</span>
            {label(preset)}
            <span className="font-semibold opacity-80">· {t("fromText")}</span>
          </span>
        ) : null}
        {fromText && showChip && onChange ? (
          <button type="button" className="min-h-8 rounded-full px-3 font-bold" style={secondary} onClick={onChange}>
            {t("change")}
          </button>
        ) : null}
        {several ? (
          <>
            <span style={{ color: "var(--muted)" }}>{t("found", { count: found.timers.length })}</span>
            <button type="button" className="min-h-8 rounded-full px-3 font-bold" style={secondary} onClick={onNext}>
              {t("next")}
            </button>
          </>
        ) : null}
        {source.from === "hand" && textHasTimer && picked ? (
          <button
            type="button"
            className="min-h-8 rounded-full px-3 font-bold"
            style={secondary}
            onClick={onRestore}
            data-testid="text-timer-restore"
          >
            {t("restore", { timer: label(picked.preset) })}
          </button>
        ) : null}
        {help}
      </div>
      {fromText && oneTimer && found.timers.length > 1 ? (
        <p className="rounded-lg px-2 py-1" style={warning}>
          {t("oneTimer")}
        </p>
      ) : null}
      {missing ? (
        <p className="rounded-lg px-2 py-1" style={warning}>
          {t(`missingNumber.${missingKind(missing.key)}`)}
        </p>
      ) : null}
    </div>
  );
}

function missingKind(key: string): "amrap" | "emom" | "intervals" {
  if (key === "amrap" || key === "edt") return "amrap";
  if (key === "intervals" || key === "billat" || key === "hrr" || key === "tabata") return "intervals";
  return "emom";
}

const secondary = { background: "var(--card)", color: "var(--text)", border: "1px solid var(--dim)" } as const;
const warning = {
  background: "color-mix(in srgb, var(--warning) 14%, var(--card))",
  color: "var(--text)",
  border: "1px solid color-mix(in srgb, var(--warning) 50%, transparent)",
} as const;
