"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { setAutoPost, SUMMARY_KEY, type SocialSummary } from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { useSession } from "@/components/session-provider";
import { useSocialSummary } from "@/components/social/use-social";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";

/** Κοινοποίηση & ορατότητα › «Ανέβαζε αυτόματα κάθε WOD» (ADR-565); unanswered reads as off. */
export function AutoPostSetting() {
  const t = useTranslations("ShareCard");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const summary = useSocialSummary();
  const enabled = summary.data?.auto_post?.enabled === true;
  const save = useMutation({
    mutationFn: (next: boolean) => setAutoPost(tokens!.access_token, next),
    onSuccess: (setting) =>
      queryClient.setQueryData<SocialSummary>(SUMMARY_KEY, (current) => (current ? { ...current, auto_post: setting } : current)),
  });
  if (summary.isPending) return <p style={{ color: "var(--dim)" }}>{t("preparing")}</p>;

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-4">
        <span id="auto-post-label" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("settingToggle")}
        </span>
        <button
          type="button"
          role="switch"
          aria-checked={enabled}
          aria-labelledby="auto-post-label"
          aria-describedby="auto-post-state"
          disabled={save.isPending || !summary.data}
          onClick={() => save.mutate(!enabled)}
          className="hit-area relative h-8 w-14 shrink-0 rounded-full disabled:opacity-60"
          style={{ background: enabled ? "var(--primary)" : "var(--panel-raised)", border: "1px solid var(--border)" }}
        >
          <span
            aria-hidden="true"
            className="absolute top-1 h-5 w-5 rounded-full transition-all"
            style={{ insetInlineStart: enabled ? "1.9rem" : "0.25rem", background: enabled ? "var(--bg)" : "var(--text)" }}
          />
        </button>
      </div>
      <p id="auto-post-state" className="text-sm" style={{ color: "var(--muted)" }}>
        {enabled ? t("settingOn") : t("settingOff")}
      </p>
      {save.error ? <ErrorNotice>{clientErrorMessage(save.error, tUi)}</ErrorNotice> : null}
    </div>
  );
}
