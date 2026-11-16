"use client";

import { useTranslations } from "next-intl";
import { useMemo, useState } from "react";

import type { ExerciseMatch } from "@/api/exercise-matches";
import { RoleDot } from "@/components/wod-goals/GoalChips";
import { Dialog } from "@/components/ui/Dialog";
import {
  allAnswered,
  groupExerciseMatches,
  initialAnswers,
  type ExerciseMatchAnswers,
  type ExerciseMatchGroup,
} from "@/lib/exercise-match-answers";

/**
 * ADR-570: before a free-text workout is published, one row per exercise the
 * matcher found (the same words found twice are one row): «Ναι» links the
 * words to the exercise, so it counts for the muscles and qualities; «Όχι»
 * keeps them plain text. A match the box confirmed before starts at «Ναι».
 * Publishing waits for an answer on every row.
 */
export function ExerciseMatchesDialog({
  matches,
  timer = null,
  onChangeTimer,
  busy,
  error,
  onBack,
  onConfirm,
}: {
  matches: ExerciseMatch[];
  /** ADR-650: the timer the text set, written out («AMRAP 12»), to confirm with «Ναι» or change. */
  timer?: string | null;
  onChangeTimer?: () => void;
  busy: boolean;
  error: string | null;
  onBack: () => void;
  onConfirm: (answers: ExerciseMatchAnswers) => void;
}) {
  const t = useTranslations("ExerciseMatches");
  const anatomy = useTranslations("Anatomy");
  const groups = useMemo(() => groupExerciseMatches(matches), [matches]);
  const [answers, setAnswers] = useState<ExerciseMatchAnswers>(() => initialAnswers(groups));
  const [timerConfirmed, setTimerConfirmed] = useState(false);
  const ready = allAnswered(groups, answers) && (timer === null || timerConfirmed);
  const answerAll = (answer: "yes" | "no") => {
    setAnswers(Object.fromEntries(groups.map((group) => [group.key, answer])));
    if (answer === "yes") setTimerConfirmed(true);
  };

  return (
    <Dialog
      onClose={onBack}
      dismissible={!busy}
      title={groups.length > 0 ? t("title") : t("timerTitle")}
      description={groups.length > 0 ? t("description") : t("timerDescription")}
      size="lg"
      testId="exercise-matches-dialog"
      error={error}
      footerStart={
        groups.length === 0 ? undefined : (
        <div className="flex flex-wrap gap-2">
          <button type="button" className="rounded-xl px-3 py-2 text-xs font-bold" style={secondary} onClick={() => answerAll("yes")} disabled={busy}>
            {t("allYes")}
          </button>
          <button type="button" className="rounded-xl px-3 py-2 text-xs font-bold" style={secondary} onClick={() => answerAll("no")} disabled={busy}>
            {t("allNo")}
          </button>
        </div>
        )
      }
      footer={
        <>
          <button type="button" className="rounded-xl px-4 py-2 text-sm font-bold" style={secondary} onClick={onBack} disabled={busy}>
            {t("back")}
          </button>
          <button
            type="button"
            className="rounded-xl px-4 py-2 text-sm font-black disabled:opacity-40"
            style={{ background: "var(--success, var(--primary))", color: "var(--bg)" }}
            disabled={!ready || busy}
            onClick={() => onConfirm(answers)}
          >
            {busy ? t("publishing") : t("publish")}
          </button>
        </>
      }
    >
      <ul className="flex flex-col gap-2">
        {timer !== null ? (
          <li
            className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border px-3 py-2"
            style={{ borderColor: "var(--dim)", background: "var(--card)" }}
            data-testid="text-timer-row"
          >
            <p className="min-w-0 flex-1 text-sm" style={{ color: "var(--text)" }}>
              {t("timerFromText")} <strong className="tabular-nums">{timer}</strong>
            </p>
            <div className="flex gap-2" role="group" aria-label={t("timerFromText")}>
              <button
                type="button"
                aria-pressed={timerConfirmed}
                className="min-h-10 min-w-11 rounded-xl px-3 text-sm font-bold"
                style={
                  timerConfirmed
                    ? { background: "color-mix(in srgb, var(--success) 16%, var(--card))", color: "var(--success)", border: "1px solid var(--success)" }
                    : secondary
                }
                onClick={() => setTimerConfirmed(true)}
                disabled={busy}
              >
                {t("yes")}
              </button>
              {onChangeTimer ? (
                <button type="button" className="min-h-10 rounded-xl px-3 text-sm font-bold" style={secondary} onClick={onChangeTimer} disabled={busy}>
                  {t("timerChange")}
                </button>
              ) : null}
            </div>
          </li>
        ) : null}
        {groups.map((group) => (
          <MatchRow
            key={group.key}
            group={group}
            answer={answers[group.key] ?? null}
            muscleName={(id) => anatomy(`muscle.${id}`)}
            onAnswer={(answer) => setAnswers((current) => ({ ...current, [group.key]: answer }))}
            disabled={busy}
          />
        ))}
      </ul>
      {!ready ? (
        <p className="mt-3 text-xs" style={{ color: "var(--muted)" }}>
          {t("answerAll")}
        </p>
      ) : null}
    </Dialog>
  );
}

const secondary = { background: "var(--card)", color: "var(--text)", border: "1px solid var(--dim)" } as const;

function MatchRow({
  group,
  answer,
  muscleName,
  onAnswer,
  disabled,
}: {
  group: ExerciseMatchGroup;
  answer: "yes" | "no" | null;
  muscleName: (id: string) => string;
  onAnswer: (answer: "yes" | "no") => void;
  disabled: boolean;
}) {
  const t = useTranslations("ExerciseMatches");
  const main = group.muscles.filter((muscle) => muscle.role === "primary").slice(0, 3);
  const rejected = answer === "no";
  return (
    <li
      className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border px-3 py-2"
      style={{
        borderColor: rejected ? "color-mix(in srgb, var(--warning) 60%, var(--danger))" : "var(--dim)",
        background: rejected ? "color-mix(in srgb, color-mix(in srgb, var(--warning) 60%, var(--danger)) 10%, var(--card))" : "var(--card)",
      }}
      data-testid="exercise-match-row"
    >
      <div className="min-w-0 flex-1">
        <p className="text-sm" style={{ color: "var(--text)" }}>
          {group.kind === "changed" ? (
            t("stillQuestion", { typed: group.typed, label: group.label })
          ) : (
            <>
              <span style={{ color: "var(--muted)" }}>«{group.typed}»</span>
              <span aria-hidden="true"> → </span>
              <span className="sr-only">{t("means")}</span>
              <strong>{group.label}</strong>
            </>
          )}
        </p>
        {main.length > 0 || group.remembered ? (
          <p className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs" style={{ color: "var(--muted)" }}>
            {main.map((muscle) => (
              <span key={muscle.id} className="inline-flex items-center gap-1">
                <RoleDot role="primary" />
                {muscleName(muscle.id)}
              </span>
            ))}
            {group.remembered ? <span>{t("remembered")}</span> : null}
          </p>
        ) : null}
      </div>
      <div className="flex flex-wrap gap-1.5" role="group" aria-label={t("answerFor", { typed: group.typed })}>
        <AnswerButton pressed={answer === "yes"} onClick={() => onAnswer("yes")} disabled={disabled} tone="yes">
          {t("yes")}
        </AnswerButton>
        <AnswerButton pressed={answer === "no"} onClick={() => onAnswer("no")} disabled={disabled} tone="no">
          {t("no")}
        </AnswerButton>
      </div>
    </li>
  );
}

function AnswerButton({
  pressed,
  onClick,
  disabled,
  tone,
  children,
}: {
  pressed: boolean;
  onClick: () => void;
  disabled: boolean;
  tone: "yes" | "no";
  children: string;
}) {
  const color = tone === "yes" ? "var(--success, var(--primary))" : "color-mix(in srgb, var(--warning) 60%, var(--danger))";
  return (
    <button
      type="button"
      aria-pressed={pressed}
      onClick={onClick}
      disabled={disabled}
      className="min-h-9 min-w-14 rounded-xl px-3 text-sm font-bold"
      style={{
        background: pressed ? color : "transparent",
        color: pressed ? "var(--bg)" : "var(--text)",
        border: `1px solid ${pressed ? color : "var(--dim)"}`,
      }}
    >
      {children}
    </button>
  );
}
