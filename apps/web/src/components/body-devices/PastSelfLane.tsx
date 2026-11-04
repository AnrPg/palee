"use client";

import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchPacer, pacerKey } from "@/api/body-devices";
import { useSession } from "@/components/session-provider";
import { DeltaChip } from "@/components/body-devices/DeltaChip";
import {
  hasPastSelf,
  latestDelta,
  paceLane,
  readPacerCompare,
  writePacerCompare,
  type PacerCompare,
} from "@/lib/body-devices";

/**
 * «Ο προηγούμενος εαυτός σου» on the timer (ADR-374, mockup d7live A): one
 * thin bar with two dots, this attempt and the previous one, and the
 * difference of the last finished round or segment. Only the person's own
 * attempts (vision §4.4). Hidden with one tap under «Προχωρημένα»; the choice
 * is remembered on this device. Split marks come from the progress the timer
 * already saves (ADR-374 amendment), so it also works after being offline.
 */
export function PastSelfLane({
  executionId,
  elapsedMs,
  marker,
}: {
  executionId: string;
  /** Active time since the start: committed segments plus the running one. */
  elapsedMs: number;
  /** Changes when a round or segment ends, to fetch the new marks. */
  marker: string;
}) {
  const t = useTranslations("BodyDevices");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const [compare, setCompare] = useState<PacerCompare>("previous");
  const [advanced, setAdvanced] = useState(false);
  useEffect(() => {
    // Read once from this device's storage after mount (no server value).
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setCompare(readPacerCompare());
  }, []);

  const pacer = useQuery({
    queryKey: pacerKey(executionId),
    enabled: Boolean(token) && compare === "previous",
    queryFn: () => fetchPacer(token!, executionId),
    staleTime: 60_000,
    retry: false,
  });

  useEffect(() => {
    // The server stores the marks with the progress save; ask again a moment after.
    const timeout = window.setTimeout(() => void queryClient.invalidateQueries({ queryKey: pacerKey(executionId) }), 2_000);
    return () => window.clearTimeout(timeout);
  }, [executionId, marker, queryClient]);

  function choose(next: PacerCompare) {
    writePacerCompare(next);
    setCompare(next);
  }

  if (compare === "hidden") {
    return (
      <div className="mb-3 flex justify-end">
        <button type="button" className="text-xs font-semibold" style={{ color: "var(--dim)" }} onClick={() => choose("previous")}>
          {t("pastSelf.show")}
        </button>
      </div>
    );
  }
  if (!hasPastSelf(pacer.data)) return null;

  const lane = paceLane(pacer.data, elapsedMs);
  const latest = latestDelta(pacer.data);

  return (
    <section
      aria-label={t("pastSelf.title")}
      data-testid="past-self-lane"
      className="mb-3 flex flex-col gap-2 rounded-2xl px-4 py-3"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-center justify-between text-xs" style={{ color: "var(--text-soft)" }}>
        <span>{t("pastSelf.you")}</span>
        <span>{t("pastSelf.previous")}</span>
      </div>
      <div className="relative h-2 rounded-full" style={{ background: "var(--panel-muted)" }} aria-hidden="true">
        <i
          className="absolute top-1/2 h-3.5 w-3.5 -translate-x-1/2 -translate-y-1/2 rounded-full"
          style={{ left: `${lane.past * 100}%`, background: "var(--muted)" }}
        />
        <i
          className="absolute top-1/2 h-3.5 w-3.5 -translate-x-1/2 -translate-y-1/2 rounded-full"
          style={{ left: `${lane.you * 100}%`, background: "var(--primary)" }}
        />
      </div>
      {latest && typeof latest.delta_ms === "number" ? (
        <div className="flex items-center justify-between gap-2">
          <span className="text-sm" style={{ color: "var(--text-soft)" }}>
            {latest.round > 0 ? t("pastSelf.round", { round: latest.round }) : latest.section_name ?? t("pastSelf.segment")}
          </span>
          <DeltaChip deltaMs={latest.delta_ms} />
        </div>
      ) : null}
      <button
        type="button"
        aria-expanded={advanced}
        onClick={() => setAdvanced(!advanced)}
        className="self-start text-xs font-semibold"
        style={{ color: "var(--dim)" }}
      >
        {t("advanced")}
      </button>
      {advanced ? (
        <div className="flex flex-wrap items-center gap-2 text-xs" style={{ color: "var(--text-soft)" }}>
          <span>{t("pastSelf.compareWith")}</span>
          <span className="rounded-full px-3 py-1 font-semibold" style={{ background: "var(--panel-muted)", color: "var(--text)" }}>
            {t("pastSelf.comparePrevious")}
          </span>
          <button type="button" className="rounded-full px-3 py-1 font-semibold" style={{ border: "1px solid var(--border)" }} onClick={() => choose("hidden")}>
            {t("pastSelf.hide")}
          </button>
        </div>
      ) : null}
    </section>
  );
}
