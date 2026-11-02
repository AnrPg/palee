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
 * up to five reviews with each author's attribution, and «Από το Google».
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
      {google.reviews.length > 0 ? (
        <ul className="flex flex-col gap-2">
          {google.reviews.map((review, index) => (
            <li key={`${review.author_name ?? "g"}-${index}`} className="flex flex-col gap-1 rounded-2xl p-3" style={{ border: "1px solid var(--border)" }}>
              <span className="flex flex-wrap items-center gap-2 text-sm">
                {review.rating ? <Stars value={review.rating} size={13} label={t("starsLabel", { stars: review.rating })} /> : null}
                {review.author_uri ? (
                  <a href={review.author_uri} target="_blank" rel="noreferrer" className="font-bold" style={{ color: "var(--text)" }}>
                    {review.author_name}
                  </a>
                ) : (
                  <b style={{ color: "var(--text)" }}>{review.author_name}</b>
                )}
                {review.relative_time ? <span className="text-xs" style={{ color: "var(--dim)" }}>{review.relative_time}</span> : null}
              </span>
              {review.text ? <p className="line-clamp-4 text-sm" style={{ color: "var(--text-soft)" }}>{review.text}</p> : null}
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  );
}
