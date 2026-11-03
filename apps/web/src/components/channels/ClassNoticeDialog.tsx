"use client";

import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { previewClassNotice, sendClassNotice, type ClassNoticeKind } from "@/api/channels";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Toggle } from "@/components/admin/finance/packages/package-ui";
import { formatClock } from "@/lib/clock";

import { useSmsError } from "./SmsConnectionSettings";
import { formatCents, inputStyle, noticeKey, smsErrorCode } from "./sms";

const MAX_TEXT = 300;

/**
 * Πρόγραμμα › μάθημα › «Ενημέρωση συμμετεχόντων» (W3 screen 4, option Γ;
 * ADR-385). Staff pick what happened (cancelled, new time, free text) and
 * see, before sending, who learns of it: in the app (free), by SMS (those
 * without the app who agreed, with the cost) and with no way at all. One
 * press sends; the same press never sends twice.
 */
export function ClassNoticeDialog({ slotId, cancelled, onClose }: { slotId: string; cancelled: boolean; onClose: () => void }) {
  const t = useTranslations("Sms");
  const locale = useLocale();
  const smsError = useSmsError();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const [kind, setKind] = useState<ClassNoticeKind>(cancelled ? "cancelled" : "changed");
  const [text, setText] = useState("");
  const [urgent, setUrgent] = useState(false);
  const [key] = useState(noticeKey);
  const ready = kind !== "free" || text.trim() !== "";
  const request = { slot_id: slotId, kind, locale, ...(kind === "free" ? { text: text.trim(), urgent } : {}) };

  const preview = useQuery({
    queryKey: ["admin", "channels", "class-notice", slotId, kind, kind === "free" ? text.trim() : "", urgent],
    queryFn: () => previewClassNotice(token!, request),
    enabled: Boolean(token) && ready,
  });
  const send = useMutation({ mutationFn: () => sendClassNotice(token!, { ...request, idempotency_key: key }) });

  const data = send.data ?? preview.data;
  const money = (cents: number) => formatCents(cents, data?.currency ?? "EUR", locale);
  const blocked = smsErrorCode(data?.sms_blocked);
  const textTooLong = text.length > MAX_TEXT;

  return (
    <Dialog
      variant="center"
      size="md"
      title={t("noticeTitle")}
      onClose={onClose}
      dismissible={!send.isPending}
      error={send.isError ? smsError(send.error) ?? undefined : undefined}
      footer={
        send.isSuccess ? (
          <div className="flex justify-end">
            <button type="button" className="rounded-full px-5 py-2 text-sm font-semibold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} onClick={onClose}>
              {t("done")}
            </button>
          </div>
        ) : (
          <div className="flex justify-end gap-2">
            <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ color: "var(--text)" }} onClick={onClose}>{t("cancel")}</button>
            <button
              type="button"
              className="rounded-full px-5 py-2 text-sm font-semibold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              disabled={!ready || textTooLong || send.isPending || !preview.data || (preview.data.in_app + preview.data.sms === 0)}
              onClick={() => send.mutate()}
              data-testid="class-notice-send"
            >
              {t("noticeSend", { count: (preview.data?.in_app ?? 0) + (preview.data?.sms ?? 0) })}
            </button>
          </div>
        )
      }
    >
      <div className="space-y-4" data-testid="class-notice">
        <SegmentPicker
          semantics="radiogroup"
          ariaLabel={t("noticeKind")}
          value={kind}
          onChange={setKind}
          options={[
            { value: "cancelled", label: t("kind_cancelled") },
            { value: "changed", label: t("kind_changed") },
            { value: "free", label: t("kind_free") },
          ]}
        />

        {kind === "free" ? (
          <div className="space-y-2">
            <label className="block text-sm font-semibold" style={{ color: "var(--text)" }} htmlFor="class-notice-text">{t("noticeText")}</label>
            <textarea
              id="class-notice-text"
              rows={3}
              value={text}
              aria-invalid={textTooLong}
              aria-describedby={textTooLong ? "class-notice-text-error" : undefined}
              onChange={(event) => setText(event.target.value)}
              className="w-full rounded-xl px-3 py-2 text-sm"
              style={inputStyle(textTooLong)}
            />
            {textTooLong ? <p id="class-notice-text-error" className="text-xs" style={{ color: "var(--danger-strong)" }}>{t("noticeTooLong", { max: MAX_TEXT })}</p> : null}
            <div className="flex items-center gap-3">
              <span className="min-w-0 flex-1 text-sm" style={{ color: "var(--text)" }}>{t("urgent")}<span className="block text-xs" style={{ color: "var(--dim)" }}>{t("urgentHint")}</span></span>
              <Toggle label={t("urgent")} checked={urgent} onChange={setUrgent} />
            </div>
          </div>
        ) : null}

        {data?.sample ? (
          <div className="rounded-2xl p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
            <p className="text-sm" style={{ color: "var(--text)" }} data-testid="class-notice-sample">{data.sample.body}</p>
            <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>
              {t("parts", { count: data.sample.segments })}
              {" · "}
              {data.sample.held_for_quiet_hours
                ? t("leavesAt", { when: formatClock(data.sample.release_at, locale) })
                : t("leavesNow")}
            </p>
          </div>
        ) : null}

        {preview.isError ? <ErrorNotice variant="field">{smsError(preview.error)}</ErrorNotice> : null}

        {data ? (
          <div className="space-y-2 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="class-notice-who">
            <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{send.isSuccess ? t("noticeSent") : t("whoLearns")}</p>
            <Line label={t("inApp")} value={`${data.in_app} · ${money(0)}`} />
            <Line label={t("bySms")} value={`${data.sms} · ${money(data.estimated_cost_cents)}`} />
            <Line label={t("noWay")} value={String(data.unreachable)} />
            {blocked ? <p className="text-xs" style={{ color: "var(--warning)" }} data-testid="class-notice-blocked">{t(`errors.${blocked}`)}</p> : null}
            {data.budget ? (
              <p className="text-xs" style={{ color: "var(--dim)" }}>{t("budgetLeft", { left: money(Math.max(0, data.budget.cap_cents - data.budget.spent_cents)) })}</p>
            ) : null}
          </div>
        ) : null}
      </div>
    </Dialog>
  );
}

function Line({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-3 text-sm">
      <span style={{ color: "var(--text-soft)" }}>{label}</span>
      <span className="font-mono tabular-nums" style={{ color: "var(--text)" }}>{value}</span>
    </div>
  );
}
