"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { confirmSmsUnsubscribe, fetchSmsUnsubscribe } from "@/api/sms-unsubscribe";
import { AuthNotice, AuthShell, primaryButtonClass, primaryButtonStyle } from "@/components/auth/AuthShell";

/**
 * ADR-390: the page behind a marketing SMS's short link. It names the box,
 * says that updates keep coming, and stops offers by SMS only when the
 * person taps «Διακοπή» (a link preview opens the page and changes nothing).
 * No sign-in; the person's number is never shown.
 */
export function SmsUnsubscribePage({ token }: { token: string }) {
  const t = useTranslations("SmsUnsubscribe");
  const link = useQuery({
    queryKey: ["public", "sms-unsubscribe", token],
    queryFn: ({ signal }) => fetchSmsUnsubscribe(token, signal),
    retry: false,
  });
  const stop = useMutation({ mutationFn: () => confirmSmsUnsubscribe(token) });

  const notFound = (error: unknown) => error instanceof ApiError && error.status === 404;
  const view = stop.data ?? link.data;

  if (link.isLoading) {
    return (
      <AuthShell title={t("title")}>
        <p className="text-center text-sm" style={{ color: "var(--dim)" }} role="status">{t("loading")}</p>
      </AuthShell>
    );
  }

  if (link.isError || !view) {
    return (
      <AuthShell title={t("title")}>
        <AuthNotice>{notFound(link.error) ? t("invalid") : t("error")}</AuthNotice>
      </AuthShell>
    );
  }

  if (view.withdrawn) {
    return (
      <AuthShell title={t("title")}>
        <div className="space-y-4" data-testid="sms-unsubscribe-done">
          <AuthNotice tone="success">{t("done", { box: view.box_name })}</AuthNotice>
          <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>{t("updatesKeepComing")}</p>
        </div>
      </AuthShell>
    );
  }

  return (
    <AuthShell title={t("title")}>
      <div className="space-y-5" data-testid="sms-unsubscribe">
        <p className="text-center text-base font-semibold" style={{ color: "var(--text)" }}>{t("question", { box: view.box_name })}</p>
        <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>{t("updatesKeepComing")}</p>
        {stop.isError ? <AuthNotice>{notFound(stop.error) ? t("invalid") : t("error")}</AuthNotice> : null}
        <button type="button" className={primaryButtonClass} style={primaryButtonStyle} disabled={stop.isPending} onClick={() => stop.mutate()}>
          {t("confirm")}
        </button>
      </div>
    </AuthShell>
  );
}
