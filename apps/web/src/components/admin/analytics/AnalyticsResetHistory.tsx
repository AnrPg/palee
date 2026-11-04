"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { fetchAnalyticsResets, undoAnalyticsMetricReset, type AnalyticsResetHistory as History } from "@/api/analytics";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { STAFF_METRICS } from "@/lib/analytics-kpi";
import { useOrganizationTimeZone } from "@/lib/organization-slug";

import { NOON_MS, useKpiFormat } from "./KpiWidgets";
import { useAnalyticsDirectory } from "./use-analytics-directory";

const PER_PAGE = 20;

type Entry = History["entries"][number];

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

/**
 * «Ρυθμίσεις › Δεδομένα › Ιστορικό μηδενισμών» (ADR-462 §4): every staff
 * reset, newest first, with who made it, the figure before it and its state;
 * an active reset can be undone (owners and admins, `reset_analytics`).
 */
export function AnalyticsResetHistory() {
  const t = useTranslations("StaffAnalytics");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const zone = useOrganizationTimeZone();
  const format = useKpiFormat();
  const directory = useAnalyticsDirectory();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const [page, setPage] = useState(1);
  const [undoing, setUndoing] = useState<Entry | null>(null);

  const query = useQuery({
    queryKey: ["admin", "analytics", "resets", page],
    enabled: Boolean(token),
    queryFn: () => fetchAnalyticsResets(token, page, PER_PAGE),
  });

  const entries = Array.isArray(query.data?.entries) ? query.data.entries : [];
  const total = typeof query.data?.total === "number" ? query.data.total : entries.length;
  const pages = Math.max(1, Math.ceil(total / PER_PAGE));

  const date = (value: string | null | undefined) => {
    if (!value || Number.isNaN(Date.parse(value))) return "—";
    return new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", year: "numeric", timeZone: zone || undefined }).format(new Date(value));
  };
  const shortDay = (value: unknown) =>
    typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)
      ? new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", timeZone: "UTC" }).format(new Date(Date.parse(value) + NOON_MS))
      : "";
  const label = (key: string) => {
    const path = ["metrics", key, "label"].join(".");
    return t.has(path) ? t(path) : key;
  };
  const person = (id: string | null) => (id && directory.staffName.get(id)) || t("history.unknownPerson");
  const before = (entry: Entry) => {
    const data = record(entry.before);
    const value = typeof data.value === "number" && Number.isFinite(data.value) ? data.value : null;
    if (value === null || data.suppressed === true) return t("kpi.suppressed");
    const unit = STAFF_METRICS[entry.metric_key]?.unit ?? "count";
    const text = unit === "rows" ? format.decimal(value, 0) : format.value(unit, value);
    const from = shortDay(data.from);
    const to = shortDay(data.to);
    return from && to ? t("history.beforeValue", { value: text, from, to }) : text;
  };

  return (
    <div className="space-y-4" data-testid="analytics-reset-history">
      <div>
        <h3 className="text-base font-black" style={{ color: "var(--text)" }}>{t("history.title")}</h3>
        <p className="mt-1 text-sm leading-6" style={{ color: "var(--muted)" }}>{t("history.description")}</p>
      </div>

      {query.error ? <ErrorNotice>{localizeError(query.error, ui)}</ErrorNotice> : null}

      {query.isLoading ? (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("kpi.loading")}</p>
      ) : entries.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("history.empty")}</p>
      ) : (
        <ul className="divide-y rounded-2xl" style={{ border: "1px solid var(--border)", borderColor: "var(--border)" }}>
          {entries.map((entry) => (
            <li key={entry.id} className="flex min-w-0 flex-wrap items-start justify-between gap-3 p-4" style={{ borderColor: "var(--border)" }} data-testid="analytics-reset-row">
              <dl className="grid min-w-0 flex-1 grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
                <dt className="sr-only">{t("history.metric")}</dt>
                <dd className="col-span-2 min-w-0 truncate font-bold" style={{ color: "var(--text)" }}>{label(entry.metric_key)}</dd>
                <dt style={{ color: "var(--muted)" }}>{t("history.date")}</dt>
                <dd className="min-w-0" style={{ color: "var(--text-soft)" }}>{date(entry.reset_at)}</dd>
                <dt style={{ color: "var(--muted)" }}>{t("history.who")}</dt>
                <dd className="min-w-0 truncate" style={{ color: "var(--text-soft)" }}>{person(entry.reset_by)}</dd>
                <dt style={{ color: "var(--muted)" }}>{t("history.before")}</dt>
                <dd className="min-w-0 tabular-nums" style={{ color: "var(--text-soft)" }}>{before(entry)}</dd>
                <dt style={{ color: "var(--muted)" }}>{t("history.status")}</dt>
                <dd className="min-w-0" style={{ color: entry.active ? "var(--success)" : "var(--muted)" }}>
                  {entry.active ? t("history.active") : t("history.undone", { date: date(entry.undone_at) })}
                </dd>
              </dl>
              {entry.active ? (
                <button
                  type="button"
                  onClick={() => setUndoing(entry)}
                  className="min-h-9 shrink-0 rounded-full px-3.5 text-sm font-semibold"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                >
                  {t("history.undo")}
                </button>
              ) : null}
            </li>
          ))}
        </ul>
      )}

      {pages > 1 ? (
        <nav className="flex items-center justify-between gap-3 text-sm" aria-label={t("history.title")}>
          <button type="button" disabled={page <= 1} onClick={() => setPage((current) => current - 1)} className="min-h-9 rounded-full px-3 font-semibold disabled:opacity-40" style={{ color: "var(--primary-strong)" }}>
            {t("history.previous")}
          </button>
          <span style={{ color: "var(--muted)" }}>{t("history.page", { page, pages })}</span>
          <button type="button" disabled={page >= pages} onClick={() => setPage((current) => current + 1)} className="min-h-9 rounded-full px-3 font-semibold disabled:opacity-40" style={{ color: "var(--primary-strong)" }}>
            {t("history.next")}
          </button>
        </nav>
      ) : null}

      {undoing ? <UndoDialog entry={undoing} label={label(undoing.metric_key)} token={token} onClose={() => setUndoing(null)} /> : null}
    </div>
  );
}

function UndoDialog({ entry, label, token, onClose }: { entry: Entry; label: string; token: string; onClose: () => void }) {
  const t = useTranslations("StaffAnalytics");
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const undo = useMutation({
    mutationFn: () => undoAnalyticsMetricReset(token, entry.id),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["admin", "analytics"] }),
        queryClient.invalidateQueries({ queryKey: ["admin", "finance", "summary"] }),
      ]);
      onClose();
    },
  });

  return (
    <Dialog
      onClose={onClose}
      title={t("history.undoTitle", { label })}
      size="sm"
      dismissible={!undo.isPending}
      error={undo.error ? localizeError(undo.error, ui) : undefined}
      footer={
        <>
          <DialogButton onClick={onClose} disabled={undo.isPending}>
            {t("history.cancel")}
          </DialogButton>
          <DialogButton tone="primary" onClick={() => undo.mutate()} disabled={undo.isPending} testId="analytics-undo-confirm">
            {t("history.undoConfirm")}
          </DialogButton>
        </>
      }
    >
      <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>{t("history.undoBody")}</p>
    </Dialog>
  );
}
