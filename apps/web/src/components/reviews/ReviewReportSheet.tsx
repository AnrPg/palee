"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslations } from "next-intl";

import {
  MY_BOX_REVIEWS_KEY,
  REVIEW_REPORT_NOTE_MAX,
  REVIEW_REPORT_REASONS,
  STAFF_BOX_REVIEWS_KEY,
  reportBoxReview,
  reportBoxReviewAsBox,
  reportNoteRequired,
  type BoxReviewReportReason,
} from "@/api/box-site";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * «Αναφορά κριτικής» (ADR-397, option A): one sheet shaped like «Γράψε
 * κριτική», the six fixed reasons as a radio list and a note under them,
 * required only for «Παράνομο περιεχόμενο» and «Κάτι άλλο». Only the Palee
 * team sees the report and decides; the review stays up until then, and the
 * box can never hide a review on its own. `asBox` sends it as the box
 * (staff who reply as the box) instead of as a member.
 */
export function ReviewReportSheet({ token, reviewId, asBox = false, onClose }: { token: string; reviewId: string; asBox?: boolean; onClose: () => void }) {
  const t = useTranslations("BoxReviews.report");
  const tReviews = useTranslations("BoxReviews");
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const [reason, setReason] = useState<BoxReviewReportReason | null>(null);
  const [note, setNote] = useState("");
  const [errors, setErrors] = useState<{ reason?: boolean; note?: boolean }>({});
  const noteRequired = reportNoteRequired(reason);
  const send = useMutation({
    mutationFn: () => {
      const body = { reason: reason!, note: note.trim() || null };
      return asBox ? reportBoxReviewAsBox(token, reviewId, body) : reportBoxReview(token, reviewId, body);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: asBox ? STAFF_BOX_REVIEWS_KEY : MY_BOX_REVIEWS_KEY });
    },
  });

  if (send.isSuccess) {
    return (
      <Dialog
        onClose={onClose}
        title={t("doneTitle")}
        size="sm"
        variant="sheet"
        testId="review-report-done"
        footer={
          <button type="button" onClick={onClose} className="min-h-11 rounded-2xl px-5 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
            {t("ok")}
          </button>
        }
      >
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("doneText")}</p>
      </Dialog>
    );
  }

  return (
    <Dialog
      onClose={onClose}
      title={t("title")}
      description={asBox ? t("hintBox") : t("hint")}
      size="md"
      variant="sheet"
      testId="review-report-sheet"
      dismissible={!send.isPending}
      onSubmit={() => {
        const next = { reason: reason === null, note: noteRequired && note.trim().length === 0 };
        setErrors(next);
        if (!next.reason && !next.note) send.mutate();
      }}
      footer={
        <>
          <button type="button" onClick={onClose} className="min-h-11 px-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {tReviews("cancel")}
          </button>
          <button type="submit" disabled={send.isPending} className="min-h-11 rounded-2xl px-5 text-sm font-bold disabled:opacity-60" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} data-testid="review-report-send">
            {send.isPending ? t("sending") : t("send")}
          </button>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        {send.error ? <ErrorNotice>{localizeError(send.error, ui)}</ErrorNotice> : null}
        <div
          role="radiogroup"
          aria-label={t("reasonLabel")}
          aria-invalid={errors.reason || undefined}
          aria-describedby={errors.reason ? "review-report-reason-error" : undefined}
          className="flex flex-col overflow-hidden rounded-2xl"
          style={{ border: `1px solid ${errors.reason ? "var(--danger)" : "var(--border)"}` }}
        >
          {REVIEW_REPORT_REASONS.map((key, index) => {
            const checked = reason === key;
            return (
              <button
                key={key}
                type="button"
                role="radio"
                aria-checked={checked}
                onClick={() => {
                  setReason(key);
                  setErrors({});
                }}
                className="flex min-h-12 items-center gap-3 px-4 py-2.5 text-start"
                style={{ borderTop: index === 0 ? undefined : "1px solid var(--border)", background: checked ? "var(--panel-muted)" : "transparent" }}
                data-testid={`review-report-reason-${key}`}
              >
                <span
                  aria-hidden
                  className="grid h-5 w-5 shrink-0 place-items-center rounded-full"
                  style={{ border: `2px solid ${checked ? "var(--primary)" : "var(--border-strong)"}` }}
                >
                  {checked ? <span className="h-2.5 w-2.5 rounded-full" style={{ background: "var(--primary)" }} /> : null}
                </span>
                <span className="flex flex-col">
                  <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`reasons.${key}`)}</span>
                  {key === "personal_data" ? <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t("personalDataHint")}</span> : null}
                </span>
              </button>
            );
          })}
        </div>
        {errors.reason ? <FieldError id="review-report-reason-error">{t("reasonRequired")}</FieldError> : null}
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{noteRequired ? t("noteRequiredLabel") : t("note")}</span>
          <textarea
            value={note}
            onChange={(event) => {
              setNote(event.target.value);
              if (errors.note) setErrors({});
            }}
            rows={3}
            maxLength={REVIEW_REPORT_NOTE_MAX}
            placeholder={t("notePlaceholder")}
            aria-invalid={errors.note || undefined}
            aria-describedby={errors.note ? "review-report-note-error" : undefined}
            className="w-full rounded-2xl px-3.5 py-2.5 text-sm"
            style={{ background: "var(--bg)", border: `1px solid ${errors.note ? "var(--danger)" : "var(--border)"}`, color: "var(--text)" }}
            data-testid="review-report-note"
          />
        </label>
        {errors.note ? <FieldError id="review-report-note-error">{t("noteRequired")}</FieldError> : null}
      </div>
    </Dialog>
  );
}
