"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import {
  PROGRESS_RESET_AFFECTED_KEYS,
  resetProgressMetric,
  type MemberMetricKey,
  type MetricBaselines,
} from "@/api/progress-resets";
import { HelpIcon } from "@/components/InfoModal";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { useUiTranslations } from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";

/**
 * ADR-462 §5 (ANR: subtle, never a new button on the card): a Πρόοδος
 * widget's own «?» infobox, «Τι μετρά · Πώς υπολογίζεται · Αν αλλάξει» for
 * that widget, with a small «Μηδενισμός από σήμερα» link at its foot. The
 * link asks first (ui/Dialog), then POSTs the member reset and refetches
 * Πρόοδος, its depth slots and the history. Only the member sees the change.
 */

/** Message ids of each member metric under `ProgressResets.metric.*` and `.info.*`. */
export const METRIC_MESSAGE_ID: Record<MemberMetricKey, string> = {
  "progress.totals": "totals",
  "progress.weekly": "weekly",
  "progress.consistency": "consistency",
  "progress.score_history": "scoreHistory",
  "progress.exercise_loads": "exerciseLoads",
  "progress.by_source": "bySource",
  "progress.pr_timeline": "prTimeline",
  "progress.depth.coverage": "depthCoverage",
  "progress.depth.qualities": "depthQualities",
  "progress.depth.load": "depthLoad",
};

export const RESET_HISTORY_HREF = "/me/settings/progress-resets";

/** The baseline of one metric as a Date, or null without one (a stub may send none). */
export function baselineOf(baselines: MetricBaselines | null | undefined, key: MemberMetricKey): Date | null {
  const at = baselines?.[key];
  if (!at) return null;
  const date = new Date(at);
  return Number.isNaN(date.getTime()) ? null : date;
}

/**
 * «από 4 Νοε» next to a title. It takes no width of its own: it fills what
 * the title row leaves and truncates, so a card's header never wraps or
 * moves because of it.
 */
export function SinceBadge({ since }: { since: Date | null }) {
  const t = useTranslations("ProgressResets");
  const format = useFormatter();
  if (!since) return null;
  const short = format.dateTime(since, { day: "numeric", month: "short" });
  const full = format.dateTime(since, { dateStyle: "long" });
  return (
    <span
      className="w-0 min-w-0 grow truncate text-[11px] font-medium normal-case tracking-normal"
      style={{ color: "var(--dim)" }}
      title={t("sinceTitle", { date: full })}
      data-testid="metric-since"
    >
      <span aria-hidden="true">{t("since", { date: short })}</span>
      <span className="sr-only">{t("sinceTitle", { date: full })}</span>
    </span>
  );
}

/** The «?» of a widget and its badge, for a title row (ClientCard `titleAside`). */
export function MetricTitleAside(props: MetricInfoProps) {
  return (
    <>
      <MetricInfo {...props} />
      <SinceBadge since={props.since} />
    </>
  );
}

type MetricInfoProps = {
  metricKey: MemberMetricKey;
  /** The widget's title as the card shows it. */
  title: string;
  since: Date | null;
  /** Widget-specific lines kept from an older infobox, after the three sections. */
  children?: ReactNode;
};

export function MetricInfo({ metricKey, title, since, children }: MetricInfoProps) {
  const t = useTranslations("ProgressResets");
  const i18n = useUiTranslations();
  const format = useFormatter();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [step, setStep] = useState<"info" | "confirm" | null>(null);
  const id = METRIC_MESSAGE_ID[metricKey];

  const reset = useMutation({
    mutationFn: () => resetProgressMetric(tokens!.access_token, metricKey),
    onSuccess: async () => {
      await Promise.all(
        PROGRESS_RESET_AFFECTED_KEYS.map((queryKey) => queryClient.invalidateQueries({ queryKey: [...queryKey] })),
      );
      setStep(null);
    },
  });

  const close = () => {
    if (reset.isPending) return;
    reset.reset();
    setStep(null);
  };

  return (
    <>
      <HelpIcon tooltip={title} onClick={() => setStep("info")} />
      {step === "info" ? (
        <Dialog onClose={close} title={title} size="md" variant="center">
          <div className="space-y-3 text-sm leading-6" style={{ color: "var(--muted)" }}>
            <p>
              <strong style={{ color: "var(--text)" }}>{t("what")}</strong> {t(`info.${id}.what`)}
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>{t("how")}</strong> {t(`info.${id}.how`)}
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>{t("change")}</strong> {t(`info.${id}.change`)}
            </p>
            {children}
            <div className="flex flex-wrap items-center gap-x-4 gap-y-1 border-t pt-3 text-xs" style={{ borderColor: "var(--border)" }}>
              {since ? (
                <span style={{ color: "var(--dim)" }}>
                  {t("countingSince", { date: format.dateTime(since, { dateStyle: "long" }) })}{" "}
                  <Link href={RESET_HISTORY_HREF} className="font-semibold" style={{ color: "var(--primary)" }}>
                    {t("history.title")}
                  </Link>
                </span>
              ) : null}
              <button
                type="button"
                onClick={() => setStep("confirm")}
                className="min-h-8 font-semibold underline-offset-2 hover:underline"
                style={{ color: "var(--muted)" }}
              >
                {t("reset")}
              </button>
            </div>
          </div>
        </Dialog>
      ) : null}
      {step === "confirm" ? (
        <Dialog
          onClose={close}
          title={t("confirmTitle", { metric: title })}
          size="sm"
          variant="center"
          dismissible={!reset.isPending}
          error={reset.isError ? localizeError(reset.error, i18n) : undefined}
          footer={
            <>
              <button
                type="button"
                onClick={close}
                disabled={reset.isPending}
                className="min-h-11 rounded-xl px-4 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--panel-muted)", color: "var(--text)", border: "1px solid var(--border)" }}
              >
                {t("cancel")}
              </button>
              <button
                type="button"
                onClick={() => reset.mutate()}
                disabled={reset.isPending || !tokens}
                className="min-h-11 rounded-xl px-4 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              >
                {reset.isPending ? t("resetting") : t("confirm")}
              </button>
            </>
          }
        >
          <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>
            {t("confirmBody")}
          </p>
        </Dialog>
      ) : null}
    </>
  );
}
