"use client";

import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useId, useState } from "react";

import type { ProgressRange } from "@/api/account-training";
import {
  fetchFitnessProfile,
  fitnessProfileKey,
  type Division,
  type FitnessDomain,
  type FitnessFocus,
} from "@/api/training-floor";
import { LoadingLine } from "@/components/client/ClientPage";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { AdvancedDisclosure } from "@/components/settings/AdvancedSettings";
import { formatDateKey } from "@/lib/local-date";
import { changeDirection, orderedDomains, reasonValue } from "@/lib/training-floor";

import { FitnessSettingsForm } from "./FitnessSettingsForm";
import { FitnessWhySteps } from "./FitnessWhySteps";

const DIVISION_KEY = "palee:fitness-profile-division";

/** The standards the person picked on this device («Ουδέτερη» by default). */
function useStoredDivision(): [Division | null, (division: Division | null) => void] {
  const [division, setDivision] = useState<Division | null>(null);
  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(DIVISION_KEY);
      // Read once from the device after mount; the server render has none.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (stored === "women" || stored === "men") setDivision(stored);
    } catch {
      // Storage blocked: neutral standards.
    }
  }, []);
  const change = (next: Division | null) => {
    setDivision(next);
    try {
      if (next) window.localStorage.setItem(DIVISION_KEY, next);
      else window.localStorage.removeItem(DIVISION_KEY);
    } catch {
      // Storage blocked: the choice lasts for this visit.
    }
  };
  return [division, change];
}

/**
 * Πρόοδος › «Επίπεδο φυσικής κατάστασης» (ADR-358, ANR mockup d6 A; version 2,
 * ADR-395, ANR fitness v2 A in all four sections): a bar per domain with the
 * change over Πρόοδος's period right next to its name and a grey tick where
 * it stood when the period began; «Γιατί;» lays out each reading step by
 * step; then «Τι να δουλέψεις». Under «Προχωρημένα»: the standards, body
 * weight, birth year (once the age bands count) and «Τι να δείχνει». With
 * «Μόνο πρόοδος» only the direction per domain shows, with «Τίποτα» one calm
 * line. A coach's stricter choice wins and the card says so. Only the
 * person's own PRs, never other people (§4.4).
 *
 * NEEDS COACH REVIEW: the benchmark anchors behind every score
 * (`Pantheon.Domain.FitnessBenchmarks`, algorithm `fitness-profile` v2), the
 * body-weight ratios and the age percentages are reviewed by a pilot coach
 * before members rely on these numbers.
 */
export function FitnessProfileCard({ range = "all" }: { range?: ProgressRange }) {
  const t = useTranslations("TrainingFloor");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [division, setDivision] = useStoredDivision();
  const [advancedOpen, setAdvancedOpen] = useState(false);
  const query = useQuery({
    queryKey: fitnessProfileKey(division, range),
    enabled: Boolean(token),
    queryFn: () => fetchFitnessProfile(token!, division, range),
    placeholderData: (previous) => previous,
    staleTime: 60_000,
  });

  if (query.isPending) return <LoadingLine />;
  // Πρόοδος has many cards; a failed one stays out of the way.
  // A malformed answer (no domains list, no algorithm) also stays out of the way.
  if (query.isError || !Array.isArray(query.data?.domains) || !query.data.algorithm) return null;
  const profile = query.data;
  const mode = profile.display?.mode ?? "all";
  const byCoach = profile.display?.set_by === "coach";
  const domains = orderedDomains(profile.domains);
  const scored = domains.some((domain) => typeof domain.score === "number");
  const tested = domains.some((domain) => domain.tested);
  const since = formatDateKey(locale, profile.period_from);
  const ticks = mode === "all" && since !== null && domains.some((domain) => typeof domain.previous_score === "number");
  const ageReady = Boolean(profile.inputs?.age_ready);

  return (
    <section
      className="flex flex-col gap-3 rounded-[1.8rem] p-5"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      aria-labelledby="fitness-profile-title"
      data-testid="fitness-profile"
      data-display={mode}
    >
      <div className="flex items-baseline justify-between gap-3">
        <h2 id="fitness-profile-title" className="text-lg font-bold" style={{ color: "var(--text)" }}>
          {t("fitnessTitle")}
        </h2>
        {mode === "all" && profile.overall ? (
          <span className="flex items-baseline gap-2 text-sm" style={{ color: "var(--muted)" }}>
            <ChangeChip change={profile.overall.change} />
            {t("fitnessOverall", { score: profile.overall.score })}
          </span>
        ) : null}
      </div>

      {byCoach ? (
        <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }} data-testid="fitness-set-by-coach">
          {t("fitnessSetByCoach")}
        </p>
      ) : null}

      {mode === "none" ? (
        <p className="flex flex-wrap items-baseline gap-x-2 text-sm" style={{ color: "var(--muted)" }} data-testid="fitness-hidden">
          {t("fitnessHidden")}
          <button
            type="button"
            className="text-sm font-semibold"
            style={{ color: "var(--primary)" }}
            onClick={() => setAdvancedOpen(true)}
          >
            {t("fitnessHiddenChange")}
          </button>
        </p>
      ) : mode === "progress_only" ? (
        tested ? (
          <>
            <ul className="flex flex-col gap-2">
              {domains.map((domain) => (
                <DomainDirection key={domain.domain} domain={domain} compared={range !== "all"} />
              ))}
            </ul>
            {range === "all" ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("fitnessPickPeriod")}</p> : null}
          </>
        ) : (
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("fitnessEmpty")}</p>
        )
      ) : !scored ? (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("fitnessEmpty")}</p>
      ) : (
        <>
          <ul className="flex flex-col gap-2">
            {domains.map((domain) => (
              <DomainBar key={domain.domain} domain={domain} />
            ))}
          </ul>
          {ticks ? (
            <p className="flex items-center gap-2 text-xs" style={{ color: "var(--dim)" }}>
              <span aria-hidden="true" className="inline-block h-3 w-0.5 rounded-full" style={{ background: "var(--dim)" }} />
              {t("fitnessPreviousTick", { date: since })}
            </p>
          ) : null}
        </>
      )}

      {mode !== "none" && (scored || tested || (profile.focus ?? []).length > 0) ? (
        <Focus focus={profile.focus ?? []} injury={profile.injury_caution} />
      ) : null}

      {mode === "all" ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {t("fitnessMeta", {
            standards: division ? t(`division_${division}`) : t("fitnessNeutral"),
            version: profile.algorithm.version,
          })}
        </p>
      ) : null}
      <AdvancedDisclosure
        count={ageReady ? 4 : 3}
        testId="fitness-profile-advanced"
        open={advancedOpen}
        onOpenChange={setAdvancedOpen}
      >
        <div className="space-y-1">
          <p className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{t("fitnessStandards")}</p>
          <SegmentPicker<"neutral" | Division>
            ariaLabel={t("fitnessStandards")}
            semantics="radiogroup"
            value={division ?? "neutral"}
            onChange={(value) => setDivision(value === "neutral" ? null : value)}
            options={[
              { value: "neutral", label: t("fitnessNeutral") },
              { value: "women", label: t("division_women") },
              { value: "men", label: t("division_men") },
            ]}
          />
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("fitnessStandardsHint")}</p>
        </div>
        {profile.settings && profile.display && profile.inputs ? <FitnessSettingsForm profile={profile} /> : null}
      </AdvancedDisclosure>
    </section>
  );
}

/** «▲ +6», «▼ −3» or «ίδιο» right next to a domain's name; nothing without a comparison. */
function ChangeChip({ change }: { change: number | null | undefined }) {
  const t = useTranslations("TrainingFloor");
  const direction = changeDirection(change);
  if (direction === null || typeof change !== "number") return null;
  const label =
    direction === "up"
      ? t("fitnessChangeUp", { count: change })
      : direction === "down"
        ? t("fitnessChangeDown", { count: Math.abs(change) })
        : t("fitnessChangeSame");
  const shown = direction === "up" ? `▲ +${change}` : direction === "down" ? `▼ −${Math.abs(change)}` : t("fitnessChangeSame");
  return (
    <span
      className="rounded-full px-2 py-0.5 text-xs font-semibold tabular-nums"
      style={{
        background: "var(--panel-muted)",
        color: direction === "up" ? "var(--success)" : "var(--muted)",
      }}
      data-testid="fitness-change"
      data-direction={direction}
    >
      <span aria-hidden="true">{shown}</span>
      <span className="sr-only">{label}</span>
    </span>
  );
}

function DomainBar({ domain }: { domain: FitnessDomain }) {
  const t = useTranslations("TrainingFloor");
  const locale = useLocale();
  const id = useId();
  const [open, setOpen] = useState(false);
  const score = typeof domain.score === "number" ? domain.score : null;
  const previous = typeof domain.previous_score === "number" ? domain.previous_score : null;
  const reasons = domain.reasons ?? [];

  return (
    <li className="flex flex-col gap-1.5" data-testid={`fitness-domain-${domain.domain}`}>
      <div className="flex items-center justify-between gap-3 text-sm">
        <span className="flex min-w-0 items-center gap-2">
          <b style={{ color: "var(--text)" }}>{t(`domain_${domain.domain}`)}</b>
          <ChangeChip change={domain.change} />
        </span>
        <span className="font-mono font-bold tabular-nums" style={{ color: score === null ? "var(--dim)" : "var(--text)" }}>
          {score ?? "—"}
        </span>
      </div>
      <div
        role="meter"
        aria-label={t(`domain_${domain.domain}`)}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={score ?? 0}
        className="relative h-2 overflow-hidden rounded-full"
        style={{ background: "var(--panel-muted)" }}
      >
        <div className="h-full rounded-full" style={{ width: `${score ?? 0}%`, background: "var(--primary)" }} />
        {previous !== null ? (
          <span
            aria-hidden="true"
            className="absolute inset-y-0 w-0.5 -translate-x-1/2"
            style={{ left: `${Math.min(100, Math.max(0, previous))}%`, background: "var(--dim)" }}
            data-testid="fitness-previous-tick"
          />
        ) : null}
      </div>
      {score === null ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t(`fitnessNoTest_${domain.domain}`)}</p>
      ) : (
        <>
          <button
            type="button"
            aria-expanded={open}
            aria-controls={id}
            onClick={() => setOpen((value) => !value)}
            className="w-fit text-xs font-semibold"
            style={{ color: "var(--primary)" }}
          >
            {t("fitnessWhy")} {open ? "▴" : "▾"}
          </button>
          {open ? (
            <div id={id} className="flex flex-col gap-3 rounded-2xl p-3" style={{ background: "var(--panel-muted)" }}>
              {reasons.map((reason) => (
                <div key={`${reason.benchmark}-${reason.name}`} className="flex flex-col gap-2">
                  <b className="text-xs" style={{ color: "var(--text)" }}>
                    {t("fitnessReason", {
                      name: reason.name,
                      value: reasonValue(reason.value, reason.unit, locale),
                      points: Math.round(reason.points),
                    })}
                  </b>
                  <FitnessWhySteps reading={reason} />
                </div>
              ))}
              {domain.confidence === "low" ? (
                <p className="text-xs" style={{ color: "var(--muted)" }}>{t("fitnessLowConfidence")}</p>
              ) : null}
            </div>
          ) : null}
        </>
      )}
    </li>
  );
}

/** «Μόνο πρόοδος»: the domain and which way it moved, never a number. */
function DomainDirection({ domain, compared }: { domain: FitnessDomain; compared: boolean }) {
  const t = useTranslations("TrainingFloor");
  const direction = domain.direction ?? null;
  return (
    <li className="flex items-center justify-between gap-3 text-sm" data-testid={`fitness-domain-${domain.domain}`}>
      <b style={{ color: "var(--text)" }}>{t(`domain_${domain.domain}`)}</b>
      {!domain.tested ? (
        <span className="text-end text-xs" style={{ color: "var(--dim)" }}>{t("fitnessNotTested")}</span>
      ) : direction ? (
        <span
          className="text-xs font-semibold"
          style={{ color: direction === "up" ? "var(--success)" : "var(--muted)" }}
          data-testid="fitness-direction"
          data-direction={direction}
        >
          {direction === "up" ? "▲ " : direction === "down" ? "▼ " : ""}
          {t(`fitnessDirection_${direction}`)}
        </span>
      ) : compared ? (
        <span className="text-xs" style={{ color: "var(--dim)" }}>{t("fitnessDirectionNone")}</span>
      ) : null}
    </li>
  );
}

function Focus({ focus, injury }: { focus: FitnessFocus[]; injury: boolean }) {
  const t = useTranslations("TrainingFloor");
  if (focus.length === 0 && !injury) return null;
  return (
    <div className="rounded-2xl p-4" style={{ background: "var(--panel-muted)" }} data-testid="fitness-focus">
      <h3 className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("fitnessFocusTitle")}</h3>
      {focus.length > 0 ? (
        <ol className="mt-2 flex list-decimal flex-col gap-1 ps-5 text-sm" style={{ color: "var(--text-soft)" }}>
          {focus.map((item) => (
            <li key={`${item.kind}-${item.domain}`}>
              {t(`focus_${item.kind}`, { domain: t(`domain_${item.domain}`) })}
            </li>
          ))}
        </ol>
      ) : null}
      {injury ? <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("fitnessInjury")}</p> : null}
    </div>
  );
}
