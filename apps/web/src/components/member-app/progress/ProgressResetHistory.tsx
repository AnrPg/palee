"use client";

import Link from "next/link";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import {
  fetchProgressResets,
  isMemberMetricKey,
  PROGRESS_RESET_AFFECTED_KEYS,
  PROGRESS_RESETS_KEY,
  undoProgressReset,
  type ProgressResetEntry,
} from "@/api/progress-resets";
import { EmptyLine, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { METRIC_MESSAGE_ID } from "@/components/member-app/progress/MetricInfo";
import { useSession } from "@/components/session-provider";
import { BackLink } from "@/components/ui/BackLink";
import { Dialog } from "@/components/ui/Dialog";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Εγώ › Ρυθμίσεις › Τα δεδομένα σου › Ιστορικό μηδενισμών (ADR-462 §5): every
 * reset the member made of a Πρόοδος stat, newest first, active or undone,
 * with «Αναίρεση» (asked first) for the active ones. Only the member sees
 * these; an undo brings the stat's older figures back.
 */
export function ProgressResetHistory() {
  const t = useTranslations("ProgressResets");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [undoing, setUndoing] = useState<ProgressResetEntry | null>(null);
  const query = useQuery({
    queryKey: [...PROGRESS_RESETS_KEY],
    enabled: Boolean(token),
    queryFn: () => fetchProgressResets(token!),
  });
  const entries = [...(query.data?.entries ?? [])].sort((left, right) => right.reset_at.localeCompare(left.reset_at));

  return (
    <main className="min-h-screen px-4 py-6 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-2xl flex-col gap-4">
        <div>
          <BackLink href="/me/settings#your-data" className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
            {t("history.back")}
          </BackLink>
          <h1 className="mt-1 text-2xl font-extrabold" style={{ color: "var(--text)" }}>
            {t("history.title")}
          </h1>
          <p className="mt-1 text-sm leading-6" style={{ color: "var(--muted)" }}>
            {t("history.intro")}
          </p>
        </div>
        {query.isPending ? (
          <LoadingLine />
        ) : query.isError ? (
          <QueryProblem error={query.error} onRetry={() => void query.refetch()} />
        ) : entries.length === 0 ? (
          <EmptyLine>
            {t("history.empty")}{" "}
            <Link href="/journal/progress" className="font-semibold" style={{ color: "var(--primary)" }}>
              {t("history.openProgress")}
            </Link>
          </EmptyLine>
        ) : (
          <>
            <p className="text-xs" style={{ color: "var(--dim)" }}>
              {t("history.total", { count: query.data?.total ?? entries.length })}
            </p>
            <ul className="flex flex-col gap-2" data-testid="progress-reset-history">
              {entries.map((entry) => (
                <ResetRow key={entry.id} entry={entry} onUndo={() => setUndoing(entry)} />
              ))}
            </ul>
          </>
        )}
      </div>
      {undoing ? <UndoDialog entry={undoing} onClose={() => setUndoing(null)} /> : null}
    </main>
  );
}

function useMetricName() {
  const t = useTranslations("ProgressResets");
  return (key: string) => (isMemberMetricKey(key) ? t(`metric.${METRIC_MESSAGE_ID[key]}`) : t("metric.other"));
}

/** A number the API returned for «before» (`value`), if any. */
function beforeValue(entry: ProgressResetEntry): number | string | null {
  const value = entry.before?.value;
  return typeof value === "number" || (typeof value === "string" && value !== "") ? value : null;
}

function ResetRow({ entry, onUndo }: { entry: ProgressResetEntry; onUndo: () => void }) {
  const t = useTranslations("ProgressResets");
  const format = useFormatter();
  const name = useMetricName();
  const when = (at: string) => format.dateTime(new Date(at), { dateStyle: "medium" });
  const before = beforeValue(entry);

  return (
    <li
      className="flex flex-wrap items-center justify-between gap-3 rounded-2xl px-4 py-3"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="min-w-0">
        <p className="break-words text-sm font-semibold" style={{ color: "var(--text)" }}>
          {name(entry.metric_key)}
        </p>
        <p className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs" style={{ color: "var(--muted)" }}>
          <time dateTime={entry.reset_at}>{t("history.resetOn", { date: when(entry.reset_at) })}</time>
          {entry.active ? (
            <span
              className="rounded-full px-2 py-0.5 font-semibold"
              style={{ background: "color-mix(in srgb, var(--success) 16%, transparent)", color: "var(--text)" }}
            >
              {t("history.active")}
            </span>
          ) : (
            <span
              className="rounded-full px-2 py-0.5 font-semibold"
              style={{ background: "var(--panel-muted)", color: "var(--dim)" }}
            >
              {entry.undone_at ? t("history.undoneOn", { date: when(entry.undone_at) }) : t("history.undone")}
            </span>
          )}
          {before !== null ? (
            <span>
              {t("history.before", {
                value: typeof before === "number" ? format.number(before) : before,
              })}
            </span>
          ) : null}
        </p>
      </div>
      {entry.active ? (
        <button
          type="button"
          onClick={onUndo}
          className="min-h-11 rounded-xl px-4 text-sm font-semibold"
          style={{ background: "var(--panel-muted)", color: "var(--text)", border: "1px solid var(--border)" }}
        >
          {t("history.undo")}
        </button>
      ) : null}
    </li>
  );
}

function UndoDialog({ entry, onClose }: { entry: ProgressResetEntry; onClose: () => void }) {
  const t = useTranslations("ProgressResets");
  const i18n = useUiTranslations();
  const format = useFormatter();
  const name = useMetricName();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const undo = useMutation({
    mutationFn: () => undoProgressReset(tokens!.access_token, entry.id),
    onSuccess: async () => {
      await Promise.all(
        PROGRESS_RESET_AFFECTED_KEYS.map((queryKey) => queryClient.invalidateQueries({ queryKey: [...queryKey] })),
      );
      onClose();
    },
  });

  return (
    <Dialog
      onClose={() => (undo.isPending ? undefined : onClose())}
      title={t("history.undoTitle", { metric: name(entry.metric_key) })}
      size="sm"
      variant="center"
      dismissible={!undo.isPending}
      error={undo.isError ? localizeError(undo.error, i18n) : undefined}
      footer={
        <>
          <button
            type="button"
            onClick={onClose}
            disabled={undo.isPending}
            className="min-h-11 rounded-xl px-4 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--panel-muted)", color: "var(--text)", border: "1px solid var(--border)" }}
          >
            {t("cancel")}
          </button>
          <button
            type="button"
            onClick={() => undo.mutate()}
            disabled={undo.isPending || !tokens}
            className="min-h-11 rounded-xl px-4 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {undo.isPending ? t("history.undoing") : t("history.undo")}
          </button>
        </>
      }
    >
      <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>
        {t("history.undoBody", { date: format.dateTime(new Date(entry.reset_at), { dateStyle: "long" }) })}
      </p>
    </Dialog>
  );
}
