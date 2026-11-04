"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { fetchPacer, pacerKey, type Pacer } from "@/api/body-devices";
import { DeltaChip } from "@/components/body-devices/DeltaChip";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { hasPastSelf, headlineDelta, paceRows } from "@/lib/body-devices";
import { formatInZone } from "@/lib/zoned-time";

function usePacer(executionId: string) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: pacerKey(executionId),
    enabled: Boolean(token),
    queryFn: () => fetchPacer(token!, executionId),
    staleTime: 5 * 60_000,
    retry: false,
  });
}

/**
 * Results against the previous attempt (ADR-374, mockup d7res A): one
 * headline and, under it, the rounds or sections with their difference. As
 * precise as the previous attempt allows. Only the person sees it.
 */
export function PastSelfResultCard({ executionId }: { executionId: string }) {
  const pacer = usePacer(executionId);
  if (!hasPastSelf(pacer.data)) return null;
  return <PastSelfBody pacer={pacer.data} />;
}

/**
 * In the Journal, under a run: one quiet line («−0:14 από 3/6») that opens
 * the same comparison. Nothing when there is no previous attempt.
 */
export function PastSelfJournalLine({ executionId }: { executionId: string }) {
  const t = useTranslations("BodyDevices");
  const locale = useLocale();
  const pacer = usePacer(executionId);
  const [open, setOpen] = useState(false);
  if (!hasPastSelf(pacer.data)) return null;
  const delta = headlineDelta(pacer.data);
  if (delta === null) return null;
  return (
    <>
      <button
        type="button"
        data-testid="past-self-line"
        onClick={() => setOpen(true)}
        className="flex items-center gap-2 text-left text-xs font-semibold"
        style={{ color: "var(--text-soft)" }}
      >
        <DeltaChip deltaMs={delta} bare />
        {t("pastSelf.fromDate", { date: previousDate(pacer.data, locale) })}
      </button>
      {open ? (
        <Dialog onClose={() => setOpen(false)} title={t("pastSelf.resultTitle")} titleId={`past-self-${executionId}`} size="md">
          <PastSelfBody pacer={pacer.data} />
        </Dialog>
      ) : null}
    </>
  );
}

function previousDate(pacer: Pacer, locale: string) {
  if (!pacer.previous) return "";
  return formatInZone(pacer.previous.completed_at_utc, pacer.previous.completed_at_tz ?? null, locale, {
    day: "numeric",
    month: "numeric",
  });
}

function PastSelfBody({ pacer }: { pacer: Pacer }) {
  const t = useTranslations("BodyDevices");
  const locale = useLocale();
  const delta = headlineDelta(pacer);
  const rows = paceRows(pacer);
  const date = previousDate(pacer, locale);
  return (
    <section
      data-testid="past-self-result"
      className="flex w-full flex-col gap-3 rounded-2xl px-4 py-3"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-center justify-between gap-3">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>
          {t("pastSelf.comparedWith", { date })}
        </span>
        {delta !== null ? <DeltaChip deltaMs={delta} /> : null}
      </div>
      {rows.length > 0 ? (
        <ul className="flex flex-col gap-1.5">
          {rows.map((row) => (
            <li key={row.key} className="flex items-center justify-between gap-3 text-sm" style={{ color: "var(--text-soft)" }}>
              <span className="min-w-0 truncate">
                {row.kind === "rounds"
                  ? row.from === row.to
                    ? t("pastSelf.round", { round: row.from ?? 0 })
                    : t("pastSelf.rounds", { from: row.from ?? 0, to: row.to ?? 0 })
                  : row.name ?? t("pastSelf.segment")}
              </span>
              {row.deltaMs !== null ? <DeltaChip deltaMs={row.deltaMs} bare /> : <span style={{ color: "var(--dim)" }}>—</span>}
            </li>
          ))}
        </ul>
      ) : null}
      {pacer.precision === "sections" || pacer.precision === "finish" ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("pastSelf.noRoundsBefore")}</p>
      ) : null}
      {pacer.previous && !pacer.previous.same_workout ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("pastSelf.sameBenchmark")}</p>
      ) : null}
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("pastSelf.onlyYou")}</p>
    </section>
  );
}
