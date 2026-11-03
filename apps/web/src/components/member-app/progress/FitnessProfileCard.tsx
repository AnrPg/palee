"use client";

import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useId, useState } from "react";

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
import { orderedDomains, reasonValue } from "@/lib/training-floor";

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
 * Πρόοδος › «Επίπεδο φυσικής κατάστασης» (ADR-358, ANR mockup d6 A): a bar per
 * domain with «Γιατί;» that shows which PRs and anchors made the number, then
 * «Τι να δουλέψεις». Only the person's own PRs, never other people (§4.4).
 *
 * NEEDS COACH REVIEW: the benchmark anchors behind every score
 * (`Pantheon.Domain.FitnessBenchmarks`, algorithm `fitness-profile` v1) are
 * generic population values; a pilot coach must review them before members
 * rely on these numbers. Changing an anchor is a new algorithm version.
 */
export function FitnessProfileCard() {
  const t = useTranslations("TrainingFloor");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [division, setDivision] = useStoredDivision();
  const query = useQuery({
    queryKey: fitnessProfileKey(division),
    enabled: Boolean(token),
    queryFn: () => fetchFitnessProfile(token!, division),
    placeholderData: (previous) => previous,
    staleTime: 60_000,
  });

  if (query.isPending) return <LoadingLine />;
  // Πρόοδος has many cards; a failed one stays out of the way.
  // A malformed answer (no domains list, no algorithm) also stays out of the way.
  if (query.isError || !Array.isArray(query.data?.domains) || !query.data.algorithm) return null;
  const profile = query.data;
  const domains = orderedDomains(profile.domains);
  const scored = domains.some((domain) => domain.score !== null);

  return (
    <section
      className="flex flex-col gap-3 rounded-[1.8rem] p-5"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      aria-labelledby="fitness-profile-title"
      data-testid="fitness-profile"
    >
      <div className="flex items-baseline justify-between gap-3">
        <h2 id="fitness-profile-title" className="text-lg font-bold" style={{ color: "var(--text)" }}>
          {t("fitnessTitle")}
        </h2>
        {profile.overall ? (
          <span className="text-sm" style={{ color: "var(--muted)" }}>{t("fitnessOverall", { score: profile.overall.score })}</span>
        ) : null}
      </div>

      {!scored ? (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("fitnessEmpty")}</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {domains.map((domain) => (
            <DomainBar key={domain.domain} domain={domain} />
          ))}
        </ul>
      )}

      {scored || (profile.focus ?? []).length > 0 ? <Focus focus={profile.focus ?? []} injury={profile.injury_caution} /> : null}

      <p className="text-xs" style={{ color: "var(--dim)" }}>
        {t("fitnessMeta", {
          standards: division ? t(`division_${division}`) : t("fitnessNeutral"),
          version: profile.algorithm.version,
        })}
      </p>
      <AdvancedDisclosure count={1} testId="fitness-profile-advanced">
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
      </AdvancedDisclosure>
    </section>
  );
}

function DomainBar({ domain }: { domain: FitnessDomain }) {
  const t = useTranslations("TrainingFloor");
  const locale = useLocale();
  const id = useId();
  const [open, setOpen] = useState(false);
  const score = domain.score;

  return (
    <li className="flex flex-col gap-1.5" data-testid={`fitness-domain-${domain.domain}`}>
      <div className="flex items-center justify-between gap-3 text-sm">
        <b style={{ color: "var(--text)" }}>{t(`domain_${domain.domain}`)}</b>
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
        className="h-2 overflow-hidden rounded-full"
        style={{ background: "var(--panel-muted)" }}
      >
        <div className="h-full rounded-full" style={{ width: `${score ?? 0}%`, background: "var(--primary)" }} />
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
            <ul id={id} className="flex flex-col gap-0.5 text-xs" style={{ color: "var(--muted)" }}>
              {domain.reasons.map((reason) => (
                <li key={`${reason.benchmark}-${reason.name}`}>
                  {t("fitnessReason", {
                    name: reason.name,
                    value: reasonValue(reason.value, reason.unit, locale),
                    points: Math.round(reason.points),
                  })}
                  {reason.estimated ? ` · ${t("fitnessEstimated")}` : ""}
                  {reason.stale ? ` · ${t("fitnessStale")}` : ""}
                </li>
              ))}
              {domain.confidence === "low" ? <li>{t("fitnessLowConfidence")}</li> : null}
            </ul>
          ) : null}
        </>
      )}
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
