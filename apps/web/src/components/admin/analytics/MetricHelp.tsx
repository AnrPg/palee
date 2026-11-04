"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { resetAnalyticsMetric } from "@/api/analytics";
import { HelpPopover } from "@/components/HelpTooltip";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { isResettable } from "@/lib/analytics-kpi";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

export type HelpContent = { what: string; how?: string; good?: string; change?: string };

const PARTS = ["what", "how", "good", "change"] as const;

/**
 * The structured help of a widget: `path` is its place in the
 * `StaffAnalytics` messages (`metrics.training.no_show_rate`,
 * `widgets.team_workouts`, `pages.training`). «Καλό νούμερο» exists only
 * where a benchmark means something, so a missing part is left out.
 */
export function useHelpContent() {
  const t = useTranslations("StaffAnalytics");
  return (path: string): HelpContent => {
    const part = (name: (typeof PARTS)[number]) => (t.has(`${path}.${name}`) ? t(`${path}.${name}`) : undefined);
    return { what: part("what") ?? "", how: part("how"), good: part("good"), change: part("change") };
  };
}

/** The help as one string (what the uniqueness check compares). */
export function helpText(content: HelpContent) {
  return PARTS.map((part) => content[part] ?? "").join("\n").trim();
}

/** True when the signed-in staff member may reset box metrics (owner, admin). */
export function useCanResetAnalytics() {
  const { membership } = useSelectedMembershipRole();
  return can(membership, "reset_analytics");
}

/**
 * A widget's own «?»: what it measures, how, a good number and what to do
 * when it moves. For a resettable metric, and only for owners and admins,
 * the footer carries «Μηδενισμός από σήμερα» (ANR: no button anywhere else).
 */
export function MetricHelp({
  label,
  path,
  content,
  metricKey,
}: {
  label: string;
  /** Where the help lives in `StaffAnalytics`. */
  path?: string;
  /** Help text given directly (widgets whose copy lives elsewhere). */
  content?: HelpContent;
  /** The registry key, for the reset in the footer. */
  metricKey?: string;
}) {
  const t = useTranslations("StaffAnalytics");
  const resolve = useHelpContent();
  const help = content ?? (path ? resolve(path) : { what: "" });
  const canReset = useCanResetAnalytics() && Boolean(metricKey) && isResettable(metricKey!);
  const [confirming, setConfirming] = useState(false);

  const rows: [string, string | undefined][] = [
    [t("help.what"), help.what],
    [t("help.how"), help.how],
    [t("help.good"), help.good],
    [t("help.change"), help.change],
  ];

  return (
    <>
      <HelpPopover
        label={t("help.open", { label })}
        helpKey={path ?? metricKey ?? label}
        footer={
          canReset
            ? (close) => (
                <button
                  type="button"
                  className="text-xs font-semibold underline-offset-2 hover:underline"
                  style={{ color: "var(--primary-strong)" }}
                  onClick={() => {
                    close();
                    setConfirming(true);
                  }}
                >
                  {t("reset.action")}
                </button>
              )
            : undefined
        }
      >
        <p className="mb-1.5 text-sm font-bold" style={{ color: "var(--text)" }}>{label}</p>
        <dl className="space-y-1.5">
          {rows
            .filter(([, text]) => Boolean(text))
            .map(([term, text]) => (
              <div key={term}>
                <dt className="font-bold" style={{ color: "var(--text)" }}>{term}</dt>
                <dd>{text}</dd>
              </div>
            ))}
        </dl>
      </HelpPopover>
      {confirming && metricKey ? <ResetDialog label={label} metricKey={metricKey} onClose={() => setConfirming(false)} /> : null}
    </>
  );
}

function ResetDialog({ label, metricKey, onClose }: { label: string; metricKey: string; onClose: () => void }) {
  const t = useTranslations("StaffAnalytics");
  const ui = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const reset = useMutation({
    mutationFn: () => resetAnalyticsMetric(tokens!.access_token, metricKey),
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
      title={t("reset.title", { label })}
      size="sm"
      dismissible={!reset.isPending}
      error={reset.error ? localizeError(reset.error, ui) : undefined}
      footer={
        <>
          <DialogButton onClick={onClose} disabled={reset.isPending}>
            {t("reset.cancel")}
          </DialogButton>
          <DialogButton tone="primary" onClick={() => reset.mutate()} disabled={reset.isPending} testId="analytics-reset-confirm">
            {t("reset.confirm")}
          </DialogButton>
        </>
      }
    >
      <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>{t("reset.body")}</p>
    </Dialog>
  );
}
