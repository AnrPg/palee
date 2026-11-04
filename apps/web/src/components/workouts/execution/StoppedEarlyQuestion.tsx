"use client";

import { useUiTranslations } from "@/i18n/ui";
import type { RetirementAnswer, StoppedEarlySection } from "@/lib/retirement";

import { formatClock } from "./TimerDisplay";

const ANSWERS: { value: RetirementAnswer; key: "stoppedEarlyGaveUp" | "stoppedEarlyChoseShorter" }[] = [
  { value: "gave_up", key: "stoppedEarlyGaveUp" },
  { value: "chose_shorter", key: "stoppedEarlyChoseShorter" },
];

/**
 * ADR-549 (mockup 3B): one quiet, optional question about a section the
 * athlete stopped before its clock ran out. Unanswered, the run stays
 * «Σταμάτησε πριν τη λήξη»; «Ήθελα μικρότερο WOD» records a shorter clock.
 */
export function StoppedEarlyQuestion({
  section,
  answer,
  onAnswer,
}: {
  section: StoppedEarlySection;
  answer: RetirementAnswer | undefined;
  onAnswer: (answer: RetirementAnswer | undefined) => void;
}) {
  const i18n = useUiTranslations();
  const ran = formatClock(Math.floor(section.ran_ms / 1000));
  const planned = formatClock(Math.round(section.planned_ms / 1000));

  return (
    <div
      className="grid gap-2 rounded-xl px-4 py-3"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid={`stopped-early-${section.section_id}`}
    >
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
        {section.section_name}
      </p>
      <p className="text-xs" style={{ color: "var(--muted)" }}>
        {i18n("stoppedEarlyAt", { ran, planned })}
      </p>
      <div className="flex flex-wrap gap-2" role="group" aria-label={i18n("stoppedEarlyQuestionLabel")}>
        {ANSWERS.map((option) => {
          const on = answer === option.value;
          return (
            <button
              key={option.value}
              type="button"
              aria-pressed={on}
              onClick={() => onAnswer(on ? undefined : option.value)}
              className="min-h-9 rounded-full px-3 text-xs font-semibold"
              style={
                on
                  ? { background: "var(--text)", color: "var(--bg)", border: "1px solid var(--text)" }
                  : { background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border)" }
              }
            >
              {i18n(option.key)}
            </button>
          );
        })}
      </div>
    </div>
  );
}
