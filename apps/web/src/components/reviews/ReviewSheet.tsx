"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useLocale, useTranslations } from "next-intl";

import { MY_BOX_REVIEWS_KEY, saveMyBoxReview, type BoxReview } from "@/api/box-site";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/** Five tappable stars (a radio group). */
export function StarPicker({ value, onChange, invalid }: { value: number; onChange: (value: number) => void; invalid: boolean }) {
  const t = useTranslations("BoxReviews");
  return (
    <div role="radiogroup" aria-label={t("ratingLabel")} aria-invalid={invalid || undefined} aria-describedby={invalid ? "review-rating-error" : undefined} className="flex gap-1">
      {[1, 2, 3, 4, 5].map((star) => (
        <button
          key={star}
          type="button"
          role="radio"
          aria-checked={value === star}
          aria-label={t("starsLabel", { stars: star })}
          onClick={() => onChange(star)}
          className="grid h-11 w-11 place-items-center text-3xl leading-none"
          style={{ color: star <= value ? "var(--warning)" : invalid ? "var(--danger)" : "var(--border-strong)" }}
          data-testid={`review-star-${star}`}
        >
          ★
        </button>
      ))}
    </div>
  );
}

/**
 * Write or edit «Η κριτική μου» (ADR-386): stars and a few words, shown in
 * the app's «Κριτικές» and on the box's website with the first name only.
 */
export function ReviewSheet({ token, boxName, mine, onClose, onSaved }: { token: string; boxName: string; mine: BoxReview | null; onClose: () => void; onSaved?: () => void }) {
  const t = useTranslations("BoxReviews");
  const ui = useUiTranslations();
  const locale = useLocale();
  const queryClient = useQueryClient();
  const [rating, setRating] = useState(mine?.rating ?? 0);
  const [body, setBody] = useState(mine?.body ?? "");
  const [missing, setMissing] = useState(false);
  const save = useMutation({
    mutationFn: () => saveMyBoxReview(token, { rating, body: body.trim() || null, locale }),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: MY_BOX_REVIEWS_KEY });
      onSaved?.();
      onClose();
    },
  });
  return (
    <Dialog
      onClose={onClose}
      title={mine ? t("editTitle") : t("writeTitle", { box: boxName })}
      description={t("writeHint")}
      size="md"
      variant="sheet"
      testId="review-sheet"
      dismissible={!save.isPending}
      onSubmit={() => {
        setMissing(rating === 0);
        if (rating > 0) save.mutate();
      }}
      footer={
        <>
          <button type="button" onClick={onClose} className="min-h-11 px-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("cancel")}
          </button>
          <button type="submit" disabled={save.isPending} className="min-h-11 rounded-2xl px-5 text-sm font-bold disabled:opacity-60" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
            {t("publish")}
          </button>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        {save.error ? <ErrorNotice>{localizeError(save.error, ui)}</ErrorNotice> : null}
        <StarPicker value={rating} onChange={(value) => { setRating(value); setMissing(false); }} invalid={missing} />
        {missing ? <FieldError id="review-rating-error">{t("ratingRequired")}</FieldError> : null}
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("bodyLabel")}</span>
          <textarea value={body} onChange={(event) => setBody(event.target.value)} rows={4} maxLength={2000} className="w-full rounded-2xl px-3.5 py-2.5 text-sm" style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }} data-testid="review-body" />
        </label>
      </div>
    </Dialog>
  );
}
