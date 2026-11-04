"use client";

import Link from "next/link";
import { useLocale, useTranslations } from "next-intl";
import { useId } from "react";

import { coverUrl, positiveInt } from "./programme-page-model";
import { programmeMoney, ratingLabel, useProgrammeLabels } from "./programme-ui";

/** The fields a programme card reads; any of them may be missing (e2e stubs answer `{}`). */
export type TileProgramme = {
  id?: unknown;
  title?: unknown;
  cover_url?: unknown;
  weeks?: unknown;
  sessions_per_week?: unknown;
  level?: unknown;
  price_cents?: unknown;
  currency?: unknown;
  reviews?: { average?: number | null; count?: number | null } | null;
  rating_average?: number | null;
  rating_count?: number | null;
  organization_name?: unknown;
};

/** The cover: the coach's photo when there is one (ADR-541), else the theme strip with the title on it. */
export function ProgrammeCover({ programme, className, children }: { programme: { cover_url?: unknown }; className: string; children?: React.ReactNode }) {
  const url = coverUrl(programme);
  if (url) {
    return (
      <div className={`relative overflow-hidden ${className}`} style={{ background: "var(--panel-muted)" }}>
        {/* eslint-disable-next-line @next/next/no-img-element -- the cover from the box's public media */}
        <img src={url} alt="" className="h-full w-full object-cover" />
      </div>
    );
  }
  return (
    <div className={className} style={{ background: "linear-gradient(135deg, var(--deep), var(--primary))", color: "var(--deep-contrast)" }}>
      {children}
    </div>
  );
}

/**
 * A programme as a card (board 4κ/4μ A): cover or strip, «6 εβδ. · 4 την
 * εβδ. · Μέσο · ★ 4,8», the price and «Δες το». Used on the box website, the
 * box's programmes and the programme store.
 */
export function ProgrammeTile({ programme, href, testId }: { programme: TileProgramme; href: string; testId?: string }) {
  const t = useTranslations("Programmes");
  const locale = useLocale();
  const labels = useProgrammeLabels();
  const titleId = useId();
  const title = typeof programme.title === "string" && programme.title.trim() ? programme.title : t("title");
  const weeks = positiveInt(programme.weeks);
  const perWeek = positiveInt(programme.sessions_per_week);
  const rating = ratingLabel(locale, programme.reviews?.average ?? programme.rating_average, programme.reviews?.count ?? programme.rating_count);
  const meta = [
    weeks ? t("weeksShort", { count: weeks }) : null,
    perWeek ? t("buyer2.perWeekShort", { count: perWeek }) : null,
    labels.level(typeof programme.level === "string" ? programme.level : null) || null,
    rating ?? t("newBadge"),
  ].filter(Boolean);
  const hasCover = coverUrl(programme) !== null;
  const price = typeof programme.price_cents === "number" ? programmeMoney(locale, programme.price_cents, typeof programme.currency === "string" ? programme.currency : null) : null;
  const box = typeof programme.organization_name === "string" ? programme.organization_name : null;

  return (
    <article className="flex min-w-0 flex-col overflow-hidden rounded-3xl" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid={testId}>
      <ProgrammeCover programme={programme} className="flex h-24 items-end p-4 lg:h-28">
        <h3 id={titleId} className="line-clamp-2 break-words text-base font-extrabold lg:text-lg">{title}</h3>
      </ProgrammeCover>
      <div className="flex flex-1 flex-col gap-2 p-4">
        {hasCover ? (
          <h3 id={titleId} className="break-words text-base font-extrabold" style={{ color: "var(--text)" }}>{title}</h3>
        ) : null}
        {box ? <p className="text-xs" style={{ color: "var(--text-soft)" }}>{box}</p> : null}
        <p className="text-xs" style={{ color: "var(--muted)" }}>{meta.join(" · ")}</p>
        <div className="mt-auto flex items-center justify-between gap-3 pt-1">
          {price ? <b className="text-lg font-extrabold tabular-nums" style={{ color: "var(--text)" }}>{price}</b> : <span />}
          <Link
            href={href}
            aria-describedby={titleId}
            className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("buyer2.see")}
          </Link>
        </div>
      </div>
    </article>
  );
}
