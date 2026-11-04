"use client";

import { useLocale, useTranslations } from "next-intl";
import type { ReactNode } from "react";

import type { FitnessReason } from "@/api/training-floor";
import { formatDateKey } from "@/lib/local-date";
import { ageBandLabel, nextGap, reasonValue } from "@/lib/training-floor";

/**
 * «Γιατί;» as steps (ADR-395, ANR fitness v2 section 1 A): the PR, the 1RM
 * it stands for (Epley), ÷ body weight when the lift is read as a multiple
 * of it, the age band when it eases the standards, where the result falls
 * on the scale, and what the next level takes. Every number is the server's;
 * this only lays the arithmetic out.
 */
export function FitnessWhySteps({ reading }: { reading: FitnessReason }) {
  const t = useTranslations("TrainingFloor");
  const locale = useLocale();
  const number = (value: number, digits = 1) => new Intl.NumberFormat(locale, { maximumFractionDigits: digits }).format(value);
  const ratio = (value: number) =>
    new Intl.NumberFormat(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value);
  const kg = t("fitnessKg");
  const lift = reading.unit === "kg" && typeof reading.load === "number" && typeof reading.reps === "number";
  const onBodyWeight = reading.basis === "body_weight" && typeof reading.ratio === "number" && typeof reading.body_weight_kg === "number";
  const date = formatDateKey(locale, reading.beaten_on) ?? reading.beaten_on;
  const points = Math.round(reading.points);
  const band = ageBandLabel(reading.age_band);
  const gap = nextGap(reading);
  const anchorLabel = (value: number) => (onBodyWeight ? `${ratio(value)} ×` : reasonValue(value, reading.unit, locale));

  return (
    <ol className="flex flex-col gap-2.5" data-testid={`fitness-why-${reading.benchmark}`}>
      <Step title={t("fitnessStepPr")}>
        {lift
          ? t("fitnessStepPrLift", { name: reading.name, load: number(reading.load!), reps: reading.reps!, date })
          : t("fitnessStepPrValue", { name: reading.name, value: reasonValue(reading.value, reading.unit, locale), date })}
      </Step>

      {lift && reading.estimated ? (
        <Step title={t("fitnessStepOneRm")} testId="fitness-step-one-rm">
          <span className="font-mono tabular-nums" style={{ color: "var(--text)" }}>
            {`${number(reading.load!)} ${kg} × (1 + ${reading.reps} ÷ 30) ≈ ${number(reading.value)} ${kg}`}
          </span>
          <span className="block">{t("fitnessStepOneRmNote", { reps: reading.reps! })}</span>
        </Step>
      ) : null}

      {onBodyWeight ? (
        <Step title={t("fitnessStepRatio")} testId="fitness-step-ratio">
          <span className="font-mono tabular-nums" style={{ color: "var(--text)" }}>
            {`${number(reading.value)} ${kg} ÷ ${number(reading.body_weight_kg!)} ${kg} = ${ratio(reading.ratio!)} ×`}
          </span>
          <span className="block">{t("fitnessStepRatioNote")}</span>
        </Step>
      ) : null}

      {band && typeof reading.age_percent === "number" ? (
        <Step title={t("fitnessStepAge", { band })} testId="fitness-step-age">
          {t("fitnessStepAgeNote", { percent: number(reading.age_percent) })}
        </Step>
      ) : null}

      <Step title={t("fitnessStepScale")}>
        <Scale points={reading.points} anchors={reading.anchors} label={anchorLabel} />
        {/* The drawn scale is hidden from assistive technology; its anchors are read out here. */}
        <ul className="sr-only" data-testid="fitness-scale-anchors">
          {reading.anchors.map((anchor) => (
            <li key={anchor.points}>{`${anchorLabel(anchor.value)}: ${t("fitnessStepPoints", { points: anchor.points })}`}</li>
          ))}
        </ul>
        <span className="block">{t("fitnessStepPoints", { points })}</span>
      </Step>

      <Step title={t("fitnessStepNext")} testId="fitness-step-next">
        {!reading.next || gap === null
          ? t("fitnessStepTop")
          : reading.unit === "kg"
            ? t("fitnessStepNextKg", { points: reading.next.points, target: number(reading.next.value), more: number(gap) })
            : reading.unit === "reps"
              ? t("fitnessStepNextReps", { points: reading.next.points, target: number(reading.next.value), count: gap })
              : t("fitnessStepNextTime", {
                  points: reading.next.points,
                  target: reasonValue(reading.next.value, reading.unit, locale),
                  more: reasonValue(gap, reading.unit, locale),
                })}
      </Step>

      {reading.stale ? <li className="text-xs" style={{ color: "var(--dim)" }}>{t("fitnessStale")}</li> : null}
    </ol>
  );
}

function Step({ title, testId, children }: { title: string; testId?: string; children: ReactNode }) {
  return (
    <li className="flex flex-col gap-0.5 text-xs" style={{ color: "var(--muted)" }} data-testid={testId}>
      <b className="text-xs" style={{ color: "var(--text-soft)" }}>{title}</b>
      <div>{children}</div>
    </li>
  );
}

/** The anchors on a 0–100 line with a marker where the reading falls. */
function Scale({
  points,
  anchors,
  label,
}: {
  points: number;
  anchors: FitnessReason["anchors"];
  label: (value: number) => string;
}) {
  const clamp = (value: number) => Math.min(100, Math.max(0, value));
  return (
    <div className="relative mx-3 mb-1 mt-2 h-9" aria-hidden="true" data-testid="fitness-scale">
      <div className="absolute inset-x-0 top-1.5 h-1.5 rounded-full" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }} />
      {anchors.map((anchor) => (
        <span key={anchor.points} className="absolute top-0 flex -translate-x-1/2 flex-col items-center" style={{ left: `${clamp(anchor.points)}%` }}>
          <span className="block h-4 w-px" style={{ background: "var(--dim)" }} />
          <span className="mt-0.5 whitespace-nowrap font-mono text-[0.65rem] tabular-nums" style={{ color: "var(--dim)" }}>
            {label(anchor.value)}
          </span>
        </span>
      ))}
      <span
        className="absolute top-0.5 block h-3.5 w-3.5 -translate-x-1/2 rounded-full"
        style={{ left: `${clamp(points)}%`, background: "var(--primary)", border: "2px solid var(--panel)" }}
        data-testid="fitness-scale-marker"
      />
    </div>
  );
}
