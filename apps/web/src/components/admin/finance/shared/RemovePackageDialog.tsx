"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState, type ReactNode } from "react";

import {
  fetchPackageRemovalPreview,
  removeFinancePackage,
  type PackageRemoval,
  type PackageRemovalPreview,
} from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatCents } from "@/lib/solo-coach";

/** The reason a removal keeps (ADR-660), as the server trims it. */
export const REMOVAL_REASON_MAX = 500;

export type InvoiceChoice = "void" | "keep";

/**
 * ADR-660: whether «Αφαίρεση πακέτου» can be pressed. Staff who may cancel
 * an unpaid invoice nobody paid anything on must choose what happens to it
 * (nothing is preselected); for everyone else it stays owed.
 */
export function removalReady(preview: PackageRemovalPreview | undefined, choice: InvoiceChoice | null) {
  if (!preview) return false;
  if (preview.untouched_invoices.length === 0 || !preview.may_write_off) return true;
  return choice !== null;
}

/** What the removal sends: the choice only when one was needed. */
export function removalBody(
  preview: PackageRemovalPreview,
  choice: InvoiceChoice | null,
  reason: string,
  shareReason: boolean,
) {
  const trimmed = reason.trim();
  return {
    ...(preview.untouched_invoices.length > 0 && preview.may_write_off && choice ? { invoice_choice: choice } : {}),
    ...(trimmed ? { reason: trimmed, reason_shared: shareReason } : {}),
  };
}

/**
 * ADR-660: «Αφαίρεση πακέτου…». Says what the removal does (the package
 * gives nothing from today, upcoming bookings go after the undo minute,
 * what happens to the money) before staff confirm.
 */
export function RemovePackageDialog({
  userId,
  memberName,
  subscriptionId,
  onClose,
  onRemoved,
  onOpenRefund,
}: {
  userId: string;
  memberName: string;
  subscriptionId: string;
  onClose: () => void;
  onRemoved: (removal: PackageRemoval) => void;
  /** Opens where staff give money back (the member's panel). */
  onOpenRefund: () => void;
}) {
  const t = useTranslations("PackageRemoval");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const [choice, setChoice] = useState<InvoiceChoice | null>(null);
  const [reason, setReason] = useState("");
  const [shareReason, setShareReason] = useState(false);
  const reasonId = useId();

  const previewQuery = useQuery({
    queryKey: ["admin", "finance", "package-removal", userId, subscriptionId],
    queryFn: () => fetchPackageRemovalPreview(token, userId, subscriptionId),
    enabled: Boolean(token),
  });
  const preview = previewQuery.data?.removal;

  const mutation = useMutation({
    mutationFn: () => removeFinancePackage(token, userId, subscriptionId, removalBody(preview!, choice, reason, shareReason)),
    onSuccess: ({ removal }) => onRemoved(removal),
  });

  const money = (cents: number) => formatCents(cents, preview?.currency || "EUR", locale);
  const untouched = preview?.untouched_invoices ?? [];
  const untouchedCents = untouched.reduce((sum, invoice) => sum + invoice.total_cents, 0);

  const choiceButton = (value: InvoiceChoice, label: string) => {
    const on = choice === value;
    return (
      <button
        type="button"
        role="radio"
        aria-checked={on}
        onClick={() => setChoice(value)}
        className="flex w-full items-start rounded-2xl px-4 py-3 text-start text-sm font-semibold"
        style={{
          background: on ? "color-mix(in srgb, var(--primary) 12%, transparent)" : "var(--panel)",
          border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`,
          color: "var(--text)",
        }}
        data-testid={`package-removal-choice-${value}`}
      >
        {label}
      </button>
    );
  };

  const line = (text: ReactNode, key: string) => (
    <li key={key} className="rounded-xl px-3 py-2 text-sm" style={{ background: "var(--panel-raised)", color: "var(--text)" }}>
      {text}
    </li>
  );

  return (
    <Dialog
      onClose={onClose}
      title={preview ? t("title", { package: preview.package_name }) : t("titleLoading")}
      description={memberName}
      size="sm"
      variant="center"
      dismissible={!mutation.isPending}
      error={mutation.isError ? localizeError(mutation.error, i18n) : undefined}
      testId="package-removal"
      footer={
        <div className="flex flex-wrap w-full gap-2">
          <DialogButton onClick={onClose}>{t("cancel")}</DialogButton>
          <DialogButton
            tone="danger"
            disabled={!removalReady(preview, choice) || mutation.isPending}
            onClick={() => mutation.mutate()}
            testId="package-removal-confirm"
          >
            {mutation.isPending ? t("removing") : t("confirm")}
          </DialogButton>
        </div>
      }
    >
      {previewQuery.isError ? (
        <ErrorNotice variant="field">{localizeError(previewQuery.error, i18n)}</ErrorNotice>
      ) : !preview ? (
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("loading")}</p>
      ) : (
        <div className="flex flex-col gap-3">
          <ul className="flex flex-col gap-2">
            {line(t("fromToday"), "today")}
            {preview.upcoming_bookings > 0 ? line(t("bookings", { count: preview.upcoming_bookings }), "bookings") : null}
            {untouched.length > 0 && !preview.may_write_off ? line(t("unpaidStays", { amount: money(untouchedCents) }), "unpaid") : null}
            {preview.kept_owed_cents > 0 ? line(t("restStays", { amount: money(preview.kept_owed_cents) }), "rest") : null}
            {preview.paid_cents > 0
              ? line(
                  <span className="flex flex-wrap items-center gap-x-2">
                    {t("paidStays", { amount: money(preview.paid_cents) })}
                    <button
                      type="button"
                      onClick={onOpenRefund}
                      className="font-semibold underline-offset-2 hover:underline"
                      style={{ color: "var(--primary)" }}
                      data-testid="package-removal-refund"
                    >
                      {t("refund")}
                    </button>
                  </span>,
                  "paid",
                )
              : null}
            {untouched.length === 0 && preview.kept_owed_cents === 0 && preview.paid_cents === 0
              ? line(t("nothingOpen"), "nothing")
              : null}
          </ul>

          {untouched.length > 0 && preview.may_write_off ? (
            <div className="flex flex-col gap-2">
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                {t("unpaidTitle", { amount: money(untouchedCents) })}
              </p>
              <div role="radiogroup" aria-label={t("unpaidTitle", { amount: money(untouchedCents) })} className="flex flex-col gap-2">
                {choiceButton("void", t("choiceVoid"))}
                {choiceButton("keep", t("choiceKeep"))}
              </div>
            </div>
          ) : null}

          <label htmlFor={reasonId} className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("reason")}
            <textarea
              id={reasonId}
              className="w-full rounded-xl px-3 py-2 text-sm font-normal"
              maxLength={REMOVAL_REASON_MAX}
              onChange={(event) => setReason(event.target.value)}
              rows={2}
              style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" }}
              value={reason}
              data-testid="package-removal-reason"
            />
          </label>
          <label className="flex items-center gap-2 text-sm" style={{ color: reason.trim() ? "var(--text)" : "var(--dim)" }}>
            <input
              type="checkbox"
              className="h-5 w-5"
              checked={shareReason}
              disabled={!reason.trim()}
              onChange={(event) => setShareReason(event.target.checked)}
              data-testid="package-removal-share-reason"
            />
            {t("shareReason")}
          </label>
        </div>
      )}
    </Dialog>
  );
}
