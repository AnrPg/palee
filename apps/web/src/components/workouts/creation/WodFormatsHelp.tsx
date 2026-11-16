"use client";

import { useId, useMemo, useRef, useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import { Dialog } from "@/components/ui/Dialog";
import { timerChipLabel, type FreeTextTimerPreset } from "@/lib/free-text-timer";
import { WOD_FORMATS } from "@/lib/wod-formats/catalog";
import { readFormatLine } from "@/lib/wod-formats/parse";
import { getFormatLabels } from "@/types/workout";
import { useUiTranslations } from "@/i18n/ui";

/** The examples of the help, in the order shown; each is a line of the screen's language. */
export const HELP_EXAMPLES = ["amrap", "emom", "every", "forTime", "cap", "tabata", "intervals", "deathBy"] as const;

type Translate = ReturnType<typeof useTranslations<"WodFormatsHelp">>;

/** «12 λεπτά», «1 λεπτό και 30 δευτερόλεπτα». */
export function spokenTime(t: Translate, seconds: number): string {
  const min = Math.floor(seconds / 60);
  const sec = seconds % 60;
  if (min && sec) return t("time.minSec", { min: t("time.min", { count: min }), sec: t("time.sec", { count: sec }) });
  return min ? t("time.min", { count: min }) : t("time.sec", { count: sec });
}

/** What a timer does, in one plain sentence (ADR-650 help); null for a timer that only counts up. */
export function explainTimer(t: Translate, preset: FreeTextTimerPreset): string | null {
  const time = (seconds: number | null | undefined) => spokenTime(t, seconds ?? 0);
  switch (preset.format) {
    case "amrap":
      return preset.duration_seconds ? t("explain.amrap", { time: time(preset.duration_seconds) }) : null;
    case "emom": {
      const every = preset.interval_seconds ?? 60;
      if (!preset.rounds) return t("explain.emomOpen", { every: time(every) });
      return t("explain.emom", { every: time(every), rounds: preset.rounds, total: time(every * preset.rounds) });
    }
    case "for_time":
      return preset.duration_seconds ? t("explain.forTimeCap", { time: time(preset.duration_seconds) }) : t("explain.forTime");
    case "tabata":
    case "custom_hiit":
      return t("explain.intervals", { work: time(preset.work_seconds), rest: time(preset.rest_seconds), rounds: preset.rounds ?? 1 });
    case "death_by":
      return t("explain.deathBy", { every: time(preset.interval_seconds ?? 60) });
    default:
      return null;
  }
}

/**
 * ADR-650: «Πώς γράφω το χρονόμετρο;», the help of the text editors. Written
 * for coaches who are not at ease with computers: three steps, a box to try a
 * line, examples as «you write → what the timer does» cards (no tables), a
 * few tips, and the full list of names folded away at the end. Every example
 * is read by the same parser as the editor, so the help never promises what
 * the editor does not do.
 */
export function WodFormatsHelpButton({ freeText = false, children }: { freeText?: boolean; children?: ReactNode }) {
  const t = useTranslations("WodFormatsHelp");
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        type="button"
        className="inline-flex min-h-8 items-center gap-1.5 rounded-full px-2 text-xs font-bold underline-offset-2 hover:underline"
        style={{ color: "var(--primary)" }}
        onClick={() => setOpen(true)}
        data-testid="wod-formats-help-button"
      >
        <span
          aria-hidden="true"
          className="inline-flex h-4 w-4 items-center justify-center rounded-full text-[10px] font-black"
          style={{ border: "1.5px solid currentColor" }}
        >
          ?
        </span>
        {children ?? t("open")}
      </button>
      {open ? <WodFormatsHelp freeText={freeText} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

export function WodFormatsHelp({ freeText, onClose }: { freeText: boolean; onClose: () => void }) {
  const t = useTranslations("WodFormatsHelp");
  const root = useTranslations();
  const ui = useUiTranslations();
  const formatLabels = useMemo(() => getFormatLabels(ui), [ui]);
  const [line, setLine] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);
  const inputId = useId();

  const timed = WOD_FORMATS.filter((format) => format.timer.kind !== "none");
  const untimed = WOD_FORMATS.filter((format) => format.timer.kind === "none");
  const label = (labelKey: string) => root(labelKey as Parameters<typeof root>[0]);

  const tryExample = (text: string) => {
    setLine(text);
    inputRef.current?.focus();
  };

  return (
    <Dialog onClose={onClose} title={t("title")} description={t("intro")} size="lg" variant="panel" testId="wod-formats-help">
      <div className="space-y-6 text-sm" style={{ color: "var(--text)" }}>
        <section aria-labelledby={`${inputId}-how`}>
          <h3 id={`${inputId}-how`} className="mb-3 text-base font-bold">
            {t("howTitle")}
          </h3>
          <ol className="space-y-3">
            {(["step1", "step2", "step3"] as const).map((step, index) => (
              <li key={step} className="flex gap-3">
                <span
                  aria-hidden="true"
                  className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-sm font-black"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                >
                  {index + 1}
                </span>
                <span className="pt-0.5 leading-relaxed">{t(step)}</span>
              </li>
            ))}
          </ol>
        </section>

        <section className="rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <label htmlFor={inputId} className="mb-2 block text-base font-bold">
            {t("tryTitle")}
          </label>
          <input
            ref={inputRef}
            id={inputId}
            type="text"
            className="w-full rounded-xl border px-3 py-2.5 text-base outline-none"
            style={{ background: "var(--card)", borderColor: "var(--border-strong)", color: "var(--text)" }}
            value={line}
            onChange={(event) => setLine(event.target.value)}
            placeholder={t("tryPlaceholder")}
            aria-label={t("tryLabel")}
            autoComplete="off"
            spellCheck={false}
            data-testid="wod-formats-help-try"
          />
          <div className="mt-3 min-h-12" aria-live="polite" data-testid="wod-formats-help-result">
            {line.trim() ? <TryResult line={line} formatLabels={formatLabels} /> : null}
          </div>
        </section>

        <section aria-labelledby={`${inputId}-examples`}>
          <h3 id={`${inputId}-examples`} className="mb-3 text-base font-bold">
            {t("examplesTitle")}
          </h3>
          <ul className="space-y-2">
            {HELP_EXAMPLES.map((key) => {
              const text = t(`examples.${key}`);
              const preset = readFormatLine(text)?.preset ?? null;
              return (
                <li
                  key={key}
                  className="flex flex-col gap-2 rounded-2xl p-3 sm:flex-row sm:items-center"
                  style={{ background: "var(--card)", border: "1px solid var(--border)" }}
                  data-testid="wod-formats-help-example"
                >
                  <div className="shrink-0 sm:w-44">
                    <div className="text-[11px] font-semibold" style={{ color: "var(--muted)" }}>
                      {t("youWrite")}
                    </div>
                    <code
                      className="mt-0.5 inline-block rounded-lg px-2 py-1 text-sm font-bold"
                      style={{ background: "var(--bg)", border: "1px solid var(--border-strong)", color: "var(--text)" }}
                      dir="auto"
                    >
                      {text}
                    </code>
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="text-[11px] font-semibold" style={{ color: "var(--muted)" }}>
                      {t("itRuns")}
                    </div>
                    <p className="mt-0.5 leading-relaxed">{preset ? explainTimer(t, preset) : null}</p>
                  </div>
                  <button
                    type="button"
                    className="min-h-9 self-start rounded-full px-3 text-xs font-bold sm:self-center"
                    style={{ background: "var(--card)", color: "var(--text)", border: "1px solid var(--dim)" }}
                    onClick={() => tryExample(text)}
                  >
                    {t("tryExample")}
                  </button>
                </li>
              );
            })}
          </ul>
        </section>

        <section aria-labelledby={`${inputId}-tips`}>
          <h3 id={`${inputId}-tips`} className="mb-3 text-base font-bold">
            {t("tipsTitle")}
          </h3>
          <ul className="space-y-2">
            {(["tipMinutes", "tipSeconds", "tipClock", "tipLanguages", ...(freeText ? (["tipOneTimer"] as const) : []), "tipCheck"] as const).map(
              (tip) => (
                <li key={tip} className="flex gap-2 leading-relaxed">
                  <span aria-hidden="true" style={{ color: "var(--success)" }}>
                    ✓
                  </span>
                  <span>{t(tip)}</span>
                </li>
              ),
            )}
          </ul>
        </section>

        <details className="rounded-2xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <summary className="cursor-pointer text-sm font-bold">{t("namesTitle")}</summary>
          <NameGroup title={t("namesTimer")} names={timed.map((format) => label(format.labelKey))} />
          <NameGroup title={t("namesNoTimer")} names={untimed.map((format) => label(format.labelKey))} />
        </details>
      </div>
    </Dialog>
  );
}

function TryResult({ line, formatLabels }: { line: string; formatLabels: ReturnType<typeof getFormatLabels> }) {
  const t = useTranslations("WodFormatsHelp");
  const timerT = useTranslations("TextTimer");
  const read = readFormatLine(line.trim());
  if (!read) return <p style={{ color: "var(--muted)" }}>{t("tryNothing")}</p>;
  if (!read.preset) {
    if (read.format.timer.kind === "none") return <p style={{ color: "var(--muted)" }}>{t("tryNotAClock")}</p>;
    const kind = read.format.timer.kind === "amrap" ? "amrap" : read.format.timer.kind === "intervals" ? "intervals" : "emom";
    return <p>{timerT(`missingNumber.${kind}`)}</p>;
  }
  return (
    <div className="space-y-1.5">
      <span
        className="inline-flex min-h-8 items-center gap-1.5 rounded-full px-3 text-xs font-bold tabular-nums"
        style={{
          background: "color-mix(in srgb, var(--success) 14%, var(--card))",
          border: "1px solid var(--success)",
          color: "var(--success)",
        }}
        data-testid="wod-formats-help-chip"
      >
        <span aria-hidden="true">⏱</span>
        {t("tryResult")}: {timerChipLabel(read.preset, formatLabels[read.preset.format])}
      </span>
      <p className="leading-relaxed">{explainTimer(t, read.preset)}</p>
    </div>
  );
}

function NameGroup({ title, names }: { title: string; names: string[] }) {
  return (
    <div className="mt-3">
      <div className="mb-1.5 text-xs font-semibold" style={{ color: "var(--muted)" }}>
        {title}
      </div>
      <ul className="flex flex-wrap gap-1.5">
        {names.map((name) => (
          <li
            key={name}
            className="rounded-full px-2.5 py-1 text-xs font-semibold"
            style={{ background: "var(--card)", border: "1px solid var(--border)" }}
          >
            {name}
          </li>
        ))}
      </ul>
    </div>
  );
}
