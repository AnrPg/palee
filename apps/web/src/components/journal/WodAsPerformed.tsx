"use client";

import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";

import { asPerformedKey, fetchWorkoutAsPerformed } from "@/api/training-floor";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { journalEntryFocused, snapshotLines } from "@/lib/training-floor";
import { formatInZone } from "@/lib/zoned-time";

/**
 * ADR-357/389 (ANR mockup d3 A): under a run or a logged score, only when the
 * WOD has changed since, one quiet line that opens the WOD «όπως ήταν». In the
 * usual case (unchanged WOD, or a result from before snapshots) nothing shows.
 *
 * ADR-393: the «Το WOD άλλαξε» notification opens the Journal on the entry
 * (`?entry=<id>`); that entry's line is brought into view and outlined.
 */
export function WodAsPerformed({
  organizationId,
  kind,
  id,
}: {
  organizationId: string | null | undefined;
  kind: "execution" | "training_log";
  id: string;
}) {
  const t = useTranslations("TrainingFloor");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const { memberships } = useSelectedMembershipRole();
  const membership = memberships.find((entry) => entry.organization.id === organizationId) ?? null;
  const slug = membership?.organization.slug ?? null;
  // ADR-179: the time it was taken, on the box's clock.
  const zone = (membership?.organization as { timezone?: string | null } | undefined)?.timezone ?? null;
  const [open, setOpen] = useState(false);
  const query = useQuery({
    queryKey: asPerformedKey(slug ?? "", kind, id),
    enabled: Boolean(token && slug),
    queryFn: () => fetchWorkoutAsPerformed(token!, slug!, kind, id),
    staleTime: 5 * 60_000,
    retry: false,
  });

  const snapshot = query.data?.changed ? query.data.snapshot : null;
  const lineRef = useRef<HTMLParagraphElement>(null);
  useEffect(() => {
    const line = lineRef.current;
    if (!snapshot || !line || !journalEntryFocused(window.location.search, id)) return;
    line.style.outline = "2px solid var(--primary)";
    line.style.outlineOffset = "4px";
    line.scrollIntoView({ block: "center", behavior: "smooth" });
  }, [snapshot, id]);
  if (!snapshot) return null;
  const when = formatInZone(snapshot.taken_at, zone, locale, {
    day: "numeric",
    month: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  const lines = snapshotLines(snapshot.content as Record<string, unknown>);

  return (
    <>
      <p
        ref={lineRef}
        className="mt-2 flex flex-wrap items-center gap-x-2 rounded-md text-xs"
        style={{ color: "var(--muted)" }}
        data-testid={`wod-changed-${id}`}
      >
        {t("snapshotChanged")}
        <button type="button" onClick={() => setOpen(true)} className="font-semibold underline" style={{ color: "var(--primary)" }}>
          {t("snapshotOpen", { when })}
        </button>
      </p>
      {open ? (
        <Dialog
          onClose={() => setOpen(false)}
          title={snapshot.title ?? t("snapshotUntitled")}
          description={t("snapshotAsItWas", { when })}
          titleId={`wod-snapshot-${id}`}
          size="lg"
        >
          {lines.length > 0 ? (
            <ul className="flex flex-col gap-1 text-sm" data-testid="wod-snapshot-lines">
              {lines.map((line, index) => (
                <li key={index} className="whitespace-pre-wrap" style={{ color: "var(--text)" }}>
                  {line}
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm" style={{ color: "var(--dim)" }}>{t("snapshotEmpty")}</p>
          )}
        </Dialog>
      ) : null}
    </>
  );
}
