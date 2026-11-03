"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { boxDataExportRefusal, fetchBoxDataExports, requestBoxDataExport } from "@/api/box-data-exports";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { exportCard, formatBytes } from "@/lib/box-data-export";
import { formatInZone } from "@/lib/zoned-time";

export const BOX_DATA_EXPORT_ANCHOR = "box-data-export";

const button = "w-fit rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50";
const primary = { background: "var(--primary)", color: "var(--primary-contrast)" };

/**
 * ADR-365 / ADR-367, W7 screen 3: «Λήψη των δεδομένων του box» in
 * Ρυθμίσεις › Επιχείρηση, between the ownership transfer and closing the box.
 * Idle: «Ετοίμασε το αρχείο». Working: the owner may close the page; one
 * email comes when it is ready. Ready: «Λήψη ZIP» for 7 days, the photos and
 * PDFs in extra ZIP parts, a new file again the next day.
 */
export function BoxDataExportCard({ token, slug, email }: { token: string; slug: string | null; email?: string | null }) {
  const t = useTranslations("BoxDataExport");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const queryKey = ["box-data-exports", slug] as const;

  const exports = useQuery({
    queryKey,
    queryFn: () => fetchBoxDataExports(token),
    refetchInterval: (query) => (query.state.data?.some((item) => item.status === "pending") ? 10_000 : false),
  });

  const request = useMutation({
    mutationFn: () => requestBoxDataExport(token),
    onSuccess: () => queryClient.invalidateQueries({ queryKey }),
  });

  // The time the list was read: the card is as fresh as the data it shows.
  const card = exportCard(exports.data, exports.dataUpdatedAt);
  const refusal = boxDataExportRefusal(request.error);
  const day = (at: string) => formatInZone(at, null, locale, { day: "numeric", month: "short" });
  const when = (at: string) => formatInZone(at, null, locale, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

  const ask = (label: string) => (
    <button type="button" className={button} style={primary} disabled={request.isPending} onClick={() => request.mutate()}>
      {request.isPending ? t("preparing") : label}
    </button>
  );

  return (
    <section id={BOX_DATA_EXPORT_ANCHOR} className="scroll-mt-24 space-y-3" data-testid="box-data-export" data-state={card.kind}>
      <h3 className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("title")}</h3>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("help")}</p>

      {exports.isError ? <ErrorNotice>{t("loadError")}</ErrorNotice> : null}

      {exports.data && card.kind === "idle" ? (
        <>
          {ask(t("prepare"))}
          <p className="text-sm" style={{ color: "var(--muted)" }}>
            {card.last?.status === "expired" && card.last.expires_at
              ? t("lastExpired", { date: day(card.last.expires_at) })
              : t("lastNone")}
          </p>
        </>
      ) : null}

      {card.kind === "working" ? (
        <p className="text-sm" role="status" style={{ color: "var(--muted)" }}>
          <b style={{ color: "var(--text)" }}>{t("workingTitle")}</b>{" "}
          {email ? t("workingEmail", { email }) : t("workingNoEmail")}
        </p>
      ) : null}

      {card.kind === "failed" ? (
        <>
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("failed")}</p>
          {ask(t("prepare"))}
        </>
      ) : null}

      {card.kind === "ready" ? (
        <>
          <p className="text-sm" style={{ color: "var(--muted)" }}>
            <b style={{ color: "var(--text)" }}>{t("ready")}</b>
            {" · "}
            {when(card.export.completed_at ?? card.export.requested_at)}
            {" · "}
            {formatBytes(card.totalBytes, locale)}
            {card.export.expires_at ? ` · ${t("availableUntil", { date: day(card.export.expires_at) })}` : null}
          </p>
          {card.export.file?.download_url ? (
            <a
              href={card.export.file.download_url}
              download={card.export.file.name}
              className={`${button} inline-block`}
              style={primary}
              data-testid="box-data-export-download"
            >
              {t("download")}
            </a>
          ) : (
            <ErrorNotice>{t("linkError")}</ErrorNotice>
          )}
          {(card.export.parts ?? []).length > 0 ? (
            <div className="space-y-1 text-sm" data-testid="box-data-export-parts">
              <p style={{ color: "var(--muted)" }}>{t("partsIntro", { count: (card.export.parts ?? []).length })}</p>
              <ul className="flex flex-wrap gap-x-4 gap-y-1">
                {(card.export.parts ?? []).map((part, index) => (
                  <li key={part.name}>
                    {part.download_url ? (
                      <a href={part.download_url} download={part.name} className="font-semibold" style={{ color: "var(--primary)" }}>
                        {t("part", { number: index + 1, size: formatBytes(part.bytes, locale) })}
                      </a>
                    ) : (
                      <span style={{ color: "var(--dim)" }}>{t("part", { number: index + 1, size: formatBytes(part.bytes, locale) })}</span>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
          {card.canAskAgain ? (
            <button
              type="button"
              className="text-sm font-semibold"
              style={{ color: "var(--primary)" }}
              disabled={request.isPending}
              onClick={() => request.mutate()}
            >
              {t("prepareNew")}
            </button>
          ) : (
            <p className="text-xs" style={{ color: "var(--dim)" }}>{t("againTomorrow")}</p>
          )}
        </>
      ) : null}

      {request.isError ? (
        <ErrorNotice>{refusal === "too_soon" ? t("tooSoon") : refusal === "in_progress" ? t("inProgress") : t("requestError")}</ErrorNotice>
      ) : null}
    </section>
  );
}
