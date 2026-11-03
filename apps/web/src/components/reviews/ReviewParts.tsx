"use client";

import type { ReactNode } from "react";
import { useLocale, useTranslations } from "next-intl";

import type { BoxReview, BoxReviewModeration, GoogleListing } from "@/api/box-site";

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

/**
 * One in-app review with the box's reply under it. `menu` is its ⋯ (e.g.
 * «Αναφορά»); `reported` shows «Το ανέφερες» while the Palee team decides
 * (ADR-397).
 */
export function ReviewItem({ review, boxName, menu, reported = false }: { review: BoxReview; boxName: string; menu?: ReactNode; reported?: boolean }) {
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
        <span className="flex items-center gap-1">
          <span className="text-xs" style={{ color: "var(--dim)" }}>
            {date}
            {review.edited_at ? ` · ${t("edited")}` : ""}
          </span>
          {menu}
        </span>
      </div>
      {review.body ? <p className="whitespace-pre-line text-sm" style={{ color: "var(--text)" }}>{review.body}</p> : null}
      {review.reply ? (
        <div className="rounded-xl px-3 py-2 text-sm" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }} data-testid="box-review-reply">
          <b style={{ color: "var(--text)" }}>{t("replyFrom", { box: boxName })}</b> {review.reply.body}
        </div>
      ) : null}
      {reported ? (
        <span className="self-start rounded-full px-2.5 py-1 text-xs font-semibold" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }} data-testid="box-review-reported">
          {t("report.reported")}
        </span>
      ) : null}
    </li>
  );
}

/**
 * The statement of reasons under «Η κριτική μου» when the Palee team hid or
 * removed it (DSA Art. 17, ADR-397 option A): what happened and when, the
 * ground and whether it rests on the law or Palee's terms, that a person
 * decided, the text the team wrote, and where to seek redress.
 */
export function ModerationNotice({ moderation }: { moderation: BoxReviewModeration }) {
  const t = useTranslations("BoxReviews");
  const locale = useLocale();
  const date = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", year: "numeric" }).format(new Date(moderation.decided_at ?? moderation.moderated_at));
  const ground = moderation.ground && moderation.ground !== "no_violation" ? moderation.ground : null;
  return (
    <div role="note" className="flex flex-col gap-1.5 rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel-muted)", border: "1px solid var(--warning)", color: "var(--text)" }} data-testid="box-review-moderation">
      <b>{moderation.status === "removed" ? t("moderation.removed", { date }) : t("moderation.hidden", { date })}</b>
      {ground ? (
        <span>
          {t("moderation.ground", {
            reason: t(`report.reasons.${ground}` as "report.reasons.offensive"),
            basis: moderation.legal_basis === "law" ? t("moderation.basisLaw") : t("moderation.basisTerms"),
          })}
        </span>
      ) : null}
      <span style={{ color: "var(--text-soft)" }}>{moderation.after_report ? t("moderation.human") : t("moderation.humanNoReport")}</span>
      {moderation.statement ? <span className="whitespace-pre-line">«{moderation.statement}»</span> : null}
      <span style={{ color: "var(--text-soft)" }}>
        {moderation.contact ? t("moderation.redress", { email: moderation.contact }) : t("moderation.redressNoEmail")}
      </span>
    </div>
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
