"use client";

import { useLocale, useTranslations } from "next-intl";

import type { BoxReview, GoogleListing } from "@/api/box-site";

/** Five stars, `value` of them filled (theme colours only). */
export function Stars({ value, size = 16, label }: { value: number; size?: number; label?: string }) {
  const rounded = Math.round(value);
  return (
    <span role={label ? "img" : undefined} aria-label={label} aria-hidden={label ? undefined : true} className="inline-flex gap-0.5" style={{ fontSize: size, lineHeight: 1 }}>
      {[1, 2, 3, 4, 5].map((star) => (
        <span key={star} style={{ color: star <= rounded ? "var(--warning)" : "var(--border)" }}>★</span>
      ))}
    </span>
  );
}

/** «4,6 ★ · 12 κριτικές»: the average and its ICU-plural count. */
export function ReviewSummary({ average, count, testId }: { average: number | null; count: number; testId?: string }) {
  const t = useTranslations("BoxReviews");
  const locale = useLocale();
  if (count === 0 || average == null) return null;
  const shown = new Intl.NumberFormat(locale, { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(average);
  return (
    <p className="flex items-center gap-2 text-sm" style={{ color: "var(--text)" }} data-testid={testId}>
      <b className="text-2xl font-extrabold">{shown}</b>
      <Stars value={average} label={t("starsLabel", { stars: shown })} />
      <span style={{ color: "var(--text-soft)" }}>{t("count", { count })}</span>
    </p>
  );
}

/** One in-app review with the box's reply under it. */
export function ReviewItem({ review, boxName }: { review: BoxReview; boxName: string }) {
  const t = useTranslations("BoxReviews");
  const locale = useLocale();
  const date = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", year: "numeric" }).format(new Date(review.created_at));
  return (
    <li className="flex flex-col gap-2 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="box-review">
      <div className="flex items-center justify-between gap-3">
        <span className="flex items-center gap-2">
          <Stars value={review.rating} label={t("starsLabel", { stars: review.rating })} />
          <b className="text-sm" style={{ color: "var(--text)" }}>{review.author_name ?? t("anonymous")}</b>
        </span>
        <span className="text-xs" style={{ color: "var(--dim)" }}>
          {date}
          {review.edited_at ? ` · ${t("edited")}` : ""}
        </span>
      </div>
      {review.body ? <p className="whitespace-pre-line text-sm" style={{ color: "var(--text)" }}>{review.body}</p> : null}
      {review.reply ? (
        <div className="rounded-xl px-3 py-2 text-sm" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }} data-testid="box-review-reply">
          <b style={{ color: "var(--text)" }}>{t("replyFrom", { box: boxName })}</b> {review.reply.body}
        </div>
      ) : null}
    </li>
  );
}

/**
 * The Google rating apart from Palee's reviews (ADR-387): its own average,
 * the number of reviews and «Από το Google», with a link to the listing.
 * No review texts until a lawyer has checked Google's terms (ADR-387
 * amendment, 2026-11-03).
 */
export function GoogleReviews({ google }: { google: GoogleListing }) {
  const t = useTranslations("BoxReviews");
  const locale = useLocale();
  const rating = google.rating == null ? null : new Intl.NumberFormat(locale, { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(google.rating);
  return (
    <section className="flex flex-col gap-3" data-testid="google-reviews">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="flex items-center gap-2 text-sm" style={{ color: "var(--text)" }}>
          <b>{t("fromGoogle")}</b>
          {rating ? (
            <>
              <span className="font-extrabold">{rating}</span>
              <Stars value={google.rating ?? 0} size={14} label={t("starsLabel", { stars: rating })} />
            </>
          ) : null}
          {google.count != null ? <span style={{ color: "var(--text-soft)" }}>{t("googleCount", { count: google.count })}</span> : null}
        </p>
        {google.maps_uri ? (
          <a href={google.maps_uri} target="_blank" rel="noreferrer" className="text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>
            {t("seeOnGoogle")} ↗
          </a>
        ) : null}
      </div>
    </section>
  );
}
