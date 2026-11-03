"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useId, useState } from "react";

import {
  fetchProgrammePurchases,
  fetchProgrammeReviews,
  moderateProgrammeReview,
  PROGRAMME_HIDE_REASONS,
  programmePurchasesKey,
  programmeReviewsKey,
  refundProgrammePurchase,
  staffProgrammeKey,
  type ProgrammeHideReason,
  type ProgrammePurchase,
  type ProgrammeReview,
  type StaffProgramme,
} from "@/api/programmes";
import { useSession } from "@/components/session-provider";
import { Pill, inputClass, inputStyle, primaryButtonClass, primaryButtonStyle, secondaryButtonClass, secondaryButtonStyle } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { newIdempotencyKey } from "@/lib/training-log";

import { utcDay } from "@/components/programmes/programme-grid";
import { programmeMoney, ratingLabel, useProgrammeError } from "@/components/programmes/programme-ui";

type Tab = "purchases" | "reviews" | "versions";

/** Mockup W8 s7 A: purchases in a table, a side panel to refund; reviews hidden with a reason; versions. */
export function ProgrammeSales({ programme, tab, token }: { programme: StaffProgramme; tab: Tab; token: string }) {
  const t = useTranslations("Programmes");
  const locale = useLocale();
  const sales = programme.sales;
  const rating = ratingLabel(locale, programme.reviews?.average, programme.reviews?.count);
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap gap-x-6 gap-y-1 text-sm" style={{ color: "var(--text-soft)" }} data-testid="programme-sales-summary">
        <span>{t("purchasesCount", { count: sales?.buyers ?? 0 })}</span>
        {sales?.gross_cents ? <span>{t("revenue", { amount: programmeMoney(locale, sales.gross_cents - (sales.refunded_cents ?? 0), sales.currency) })}</span> : null}
        {rating ? <span>{rating}</span> : null}
      </div>
      {tab === "purchases" ? <Purchases programme={programme} token={token} /> : null}
      {tab === "reviews" ? <Reviews programme={programme} token={token} /> : null}
      {tab === "versions" ? <Versions programme={programme} /> : null}
    </div>
  );
}

const PURCHASE_TONE: Record<string, "success" | "warning" | "neutral" | "danger" | "primary"> = {
  active: "success",
  pending_payment: "warning",
  completed: "neutral",
  withdrawn: "danger",
  refunded: "danger",
  cancelled: "neutral",
};

function purchaseState(purchase: ProgrammePurchase, today: string) {
  if (purchase.status === "active" && purchase.starts_on > today) return "waiting";
  return purchase.status;
}

function Purchases({ programme, token }: { programme: StaffProgramme; token: string }) {
  const t = useTranslations("Programmes");
  const locale = useLocale();
  const [open, setOpen] = useState<ProgrammePurchase | null>(null);
  const purchases = useQuery({
    queryKey: programmePurchasesKey(programme.id),
    enabled: Boolean(token),
    queryFn: () => fetchProgrammePurchases(token, programme.id),
  });
  const today = new Date().toISOString().slice(0, 10);
  const date = (iso: string) => new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", timeZone: "UTC" }).format(utcDay(iso));
  const list = purchases.data ?? [];

  if (purchases.isLoading) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (purchases.isError) return <ErrorNotice>{t("loadFailed")}</ErrorNotice>;
  if (list.length === 0) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noPurchases")}</p>;

  return (
    <>
      <div className="overflow-hidden rounded-[2rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        <table className="w-full text-sm" data-testid="programme-purchases">
          <thead>
            <tr className="text-xs" style={{ color: "var(--dim)" }}>
              <th className="px-4 py-3 text-start font-semibold">{t("buyer")}</th>
              <th className="px-4 py-3 text-start font-semibold">{t("startsOn")}</th>
              <th className="px-4 py-3 text-start font-semibold">{t("state")}</th>
              <th className="px-4 py-3 text-end font-semibold">{t("amount")}</th>
            </tr>
          </thead>
          <tbody>
            {list.map((purchase) => {
              const state = purchaseState(purchase, today);
              return (
                <tr key={purchase.id} style={{ borderTop: "1px solid var(--border)" }}>
                  <td className="px-4 py-3">
                    <button type="button" className="text-start font-semibold" style={{ color: "var(--text)" }} onClick={() => setOpen(purchase)} data-testid={`programme-purchase-${purchase.id}`}>
                      {purchase.buyer?.nickname ?? t("formerBuyer")}
                    </button>
                  </td>
                  <td className="px-4 py-3" style={{ color: "var(--text-soft)" }}>{date(purchase.starts_on)}</td>
                  <td className="px-4 py-3"><Pill tone={state === "waiting" ? "primary" : PURCHASE_TONE[state] ?? "neutral"}>{t(`purchaseState.${state}`)}</Pill></td>
                  <td className="px-4 py-3 text-end tabular-nums" style={{ color: "var(--text)" }}>{programmeMoney(locale, purchase.price_cents, purchase.currency)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {open ? <RefundPanel purchase={open} programme={programme} token={token} onClose={() => setOpen(null)} /> : null}
    </>
  );
}

function RefundPanel({ purchase, programme, token, onClose }: { purchase: ProgrammePurchase; programme: StaffProgramme; token: string; onClose: () => void }) {
  const t = useTranslations("Programmes");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const programmeError = useProgrammeError();
  const amountId = useId();
  const reasonId = useId();
  const left = purchase.price_cents - (purchase.refunded_cents ?? 0);
  const suggested = Math.min(purchase.refund?.amount_cents ?? left, left);
  const [amount, setAmount] = useState((suggested / 100).toFixed(2));
  const [reason, setReason] = useState("");
  const [key] = useState(newIdempotencyKey);
  const cents = Math.round(Number(amount.replace(",", ".")) * 100);
  const invalid = !Number.isFinite(cents) || cents <= 0 || cents > left;
  const refundable = purchase.status === "active" && left > 0;

  const refund = useMutation({
    mutationFn: () => refundProgrammePurchase(token, purchase.id, { amount_cents: cents, reason: reason.trim() || undefined, idempotency_key: key }),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: programmePurchasesKey(programme.id) }),
        queryClient.invalidateQueries({ queryKey: staffProgrammeKey(programme.id), exact: true }),
      ]);
      onClose();
    },
  });

  return (
    <Dialog
      onClose={onClose}
      variant="drawer"
      size="md"
      title={purchase.buyer?.nickname ?? t("formerBuyer")}
      testId="programme-refund-panel"
      onSubmit={refundable ? () => !invalid && refund.mutate() : undefined}
      footer={
        refundable ? (
          <>
            <button type="button" onClick={onClose} className="min-h-11 px-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>{t("cancel")}</button>
            <button type="submit" disabled={invalid || refund.isPending} className={primaryButtonClass} style={primaryButtonStyle} data-testid="programme-refund">
              {t("refundButton")}
            </button>
          </>
        ) : undefined
      }
    >
      <div className="flex flex-col gap-3">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>
          {t("paid", { amount: programmeMoney(locale, purchase.price_cents, purchase.currency) })}
          {purchase.refunded_cents ? ` · ${t("refunded", { amount: programmeMoney(locale, purchase.refunded_cents, purchase.currency) })}` : ""}
        </p>
        {refundable ? (
          <>
            {purchase.refund ? (
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                {t("suggestedRefund", { amount: programmeMoney(locale, purchase.refund.amount_cents, purchase.currency) })}
                <span className="block text-xs font-normal" style={{ color: "var(--muted)" }}>{t(`ruleNote.${purchase.refund.rule}`)}</span>
              </p>
            ) : null}
            <div>
              <label htmlFor={amountId} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("amount")}</label>
              <input
                id={amountId}
                inputMode="decimal"
                className={inputClass}
                style={invalid ? { ...inputStyle, borderColor: "var(--danger)" } : inputStyle}
                value={amount}
                aria-invalid={invalid}
                onChange={(event) => setAmount(event.target.value)}
                data-testid="programme-refund-amount"
              />
              {invalid ? <p className="mt-1 text-xs" style={{ color: "var(--danger)" }}>{t("refundAmountInvalid", { amount: programmeMoney(locale, left, purchase.currency) })}</p> : null}
            </div>
            <div>
              <label htmlFor={reasonId} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("refundReason")}</label>
              <input id={reasonId} className={inputClass} style={inputStyle} maxLength={300} value={reason} onChange={(event) => setReason(event.target.value)} />
            </div>
            <p className="text-xs" style={{ color: "var(--muted)" }}>{t("refundRemovesWods")}</p>
            {refund.isError ? <ErrorNotice variant="field">{programmeError(refund.error)}</ErrorNotice> : null}
          </>
        ) : (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("nothingToRefund")}</p>
        )}
      </div>
    </Dialog>
  );
}

function Reviews({ programme, token }: { programme: StaffProgramme; token: string }) {
  const t = useTranslations("Programmes");
  const reviews = useQuery({
    queryKey: programmeReviewsKey(programme.id),
    enabled: Boolean(token),
    queryFn: () => fetchProgrammeReviews(token, programme.id),
  });
  const list = reviews.data ?? [];
  if (reviews.isLoading) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (reviews.isError) return <ErrorNotice>{t("loadFailed")}</ErrorNotice>;
  if (list.length === 0) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noReviews")}</p>;
  return (
    <ul className="flex flex-col gap-3">
      {list.map((review) => <ReviewRow key={review.id} review={review} programmeId={programme.id} token={token} />)}
    </ul>
  );
}

function ReviewRow({ review, programmeId, token }: { review: ProgrammeReview; programmeId: string; token: string }) {
  const t = useTranslations("Programmes");
  const queryClient = useQueryClient();
  const programmeError = useProgrammeError();
  const [hiding, setHiding] = useState(false);
  const [reason, setReason] = useState<ProgrammeHideReason>("abuse");
  const moderate = useMutation({
    mutationFn: (hiddenReason: ProgrammeHideReason | null) => moderateProgrammeReview(token, review.id, hiddenReason),
    onSuccess: async () => {
      setHiding(false);
      await queryClient.invalidateQueries({ queryKey: programmeReviewsKey(programmeId) });
    },
  });
  const hidden = review.status === "hidden";
  return (
    <li className="rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)", opacity: hidden ? 0.75 : 1 }} data-testid={`programme-review-${review.id}`}>
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }} aria-label={t("stars", { count: review.rating })}>{"★".repeat(review.rating)}</span>
        <span className="text-xs" style={{ color: "var(--muted)" }}>{review.author?.nickname ?? t("formerBuyer")} · {t("versionShort", { number: review.version_number })}</span>
        {hidden ? <Pill tone="neutral">{t("hiddenBecause", { reason: t(`hideReason.${review.hidden_reason ?? "abuse"}`) })}</Pill> : null}
        <span className="flex-1" />
        {hidden ? (
          <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => moderate.mutate(null)} disabled={moderate.isPending}>{t("showAgain")}</button>
        ) : (
          <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => setHiding(true)} data-testid={`programme-review-hide-${review.id}`}>{t("hide")}</button>
        )}
      </div>
      {review.body ? <p className="mt-2 text-sm" style={{ color: "var(--text-soft)" }}>{review.body}</p> : null}
      {hiding ? (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <Select className="rounded-xl px-3 py-2 text-sm" style={inputStyle} value={reason} onValueChange={(value) => setReason(value as ProgrammeHideReason)} aria-label={t("hideReasonLabel")}>
            {PROGRAMME_HIDE_REASONS.map((value) => <option key={value} value={value}>{t(`hideReason.${value}`)}</option>)}
          </Select>
          <button type="button" className={primaryButtonClass} style={primaryButtonStyle} onClick={() => moderate.mutate(reason)} disabled={moderate.isPending} data-testid={`programme-review-hide-confirm-${review.id}`}>
            {t("hide")}
          </button>
          <button type="button" className="min-h-11 px-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }} onClick={() => setHiding(false)}>{t("cancel")}</button>
        </div>
      ) : null}
      <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("neverDeleted")}</p>
      {moderate.isError ? <ErrorNotice variant="field" className="mt-2">{programmeError(moderate.error)}</ErrorNotice> : null}
    </li>
  );
}

function Versions({ programme }: { programme: StaffProgramme }) {
  const t = useTranslations("Programmes");
  const locale = useLocale();
  const versions = programme.versions ?? (programme.version ? [programme.version] : []);
  if (versions.length === 0) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noVersions")}</p>;
  const when = (iso: string) => new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(new Date(iso));
  return (
    <ul className="overflow-hidden rounded-[2rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      {[...versions].sort((a, b) => b.number - a.number).map((version, index) => (
        <li key={version.id} className="px-6 py-4" style={{ borderTop: index === 0 ? "none" : "1px solid var(--border)" }}>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("versionShort", { number: version.number })} · {t("weeks", { count: version.weeks })} · {t("wods", { count: version.days.length })}
          </p>
          <p className="text-xs" style={{ color: "var(--muted)" }}>{[when(version.published_at), version.changelog].filter(Boolean).join(" · ")}</p>
        </li>
      ))}
      <li className="px-6 py-3 text-xs" style={{ borderTop: "1px solid var(--border)", color: "var(--dim)" }}>{t("buyersKeepVersion")}</li>
    </ul>
  );
}
