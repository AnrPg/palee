"use client";

import Link from "next/link";
import type { CSSProperties, MouseEvent } from "react";
import { useTranslations } from "next-intl";

import { initials, statEntries } from "../site-data";
import { money, Photo, Stars, useSite, useSiteText, type PhotoIcon } from "../site-context";

/** One decimal, the page's way: «4,9». */
export function useRating() {
  const { locale } = useSite();
  return (value: number) => new Intl.NumberFormat(locale, { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(value);
}

/** The headline rating: Palee's members first, else Google's. */
export function useHeadlineRating() {
  const { site } = useSite();
  const format = useRating();
  const palee = site.reviews.palee;
  const google = site.reviews.google;
  if (palee && palee.count > 0 && palee.average != null) return { value: palee.average, text: format(palee.average), count: palee.count, source: "palee" as const };
  if (google?.rating) return { value: google.rating, text: format(google.rating), count: google.count ?? 0, source: "google" as const };
  return null;
}

/** «Κριτικές»: members' reviews and Google's rating, kept apart (ADR-386/387). */
export function Reviews({ limit = 3 }: { limit?: number }) {
  const { site, page } = useSite();
  const tr = useTranslations("BoxReviews");
  const format = useRating();
  const palee = site.reviews.palee;
  const google = site.reviews.google;
  const latest = (palee?.latest ?? []).slice(0, limit);
  return (
    <div data-testid="site-reviews">
      <div className="gsum">
        {palee && palee.count > 0 && palee.average != null ? (
          <span data-testid="site-reviews-average">
            <Stars value={palee.average} label={tr("starsLabel", { stars: format(palee.average) })} /> <b>{format(palee.average)}</b> · {tr("count", { count: palee.count })}
          </span>
        ) : null}
        {google?.rating ? (
          <span className="muted" data-testid="google-reviews">
            {tr("fromGoogle")}: <b>{format(google.rating)}</b>
            {google.count != null ? ` · ${tr("googleCount", { count: google.count })}` : ""}
            {google.maps_uri ? (
              <>
                {" · "}
                <a href={google.maps_uri} target="_blank" rel="noopener noreferrer">
                  {tr("seeOnGoogle")} ↗
                </a>
              </>
            ) : null}
          </span>
        ) : null}
      </div>
      {latest.length > 0 ? (
        <div className="revs">
          {latest.map((review, index) => (
            <article key={review.id} className="rev" data-rv="up" style={{ "--d": `${index * 90}ms` } as CSSProperties} data-testid="box-review">
              <Stars value={review.rating} label={tr("starsLabel", { stars: review.rating })} />
              {review.body ? <p>{review.body}</p> : null}
              <b>{review.author_name ?? tr("anonymous")}</b>
              {review.reply ? (
                <p className="reply" data-testid="box-review-reply">
                  {tr("replyFrom", { box: page.box.name })} {review.reply.body}
                </p>
              ) : null}
            </article>
          ))}
        </div>
      ) : null}
    </div>
  );
}

/** «Συχνές ερωτήσεις» as accordions. */
export function Faq({ limit }: { limit?: number }) {
  const { site } = useSite();
  const entries = limit ? site.faq.slice(0, limit) : site.faq;
  if (entries.length === 0) return null;
  return (
    <div data-testid="site-faq">
      {entries.map((entry, index) => (
        <details key={entry.id ?? index} className="faq">
          <summary>{entry.question}</summary>
          <p>{entry.answer}</p>
        </details>
      ))}
    </div>
  );
}

/** The day and month of an event, in its own zone. */
export function useEventDate() {
  const { site, locale } = useSite();
  return (event: (typeof site.events)[number]) => {
    const zone = event.time_zone || site.time_zone;
    const at = new Date(event.starts_at);
    const safe = (options: Intl.DateTimeFormatOptions) => {
      try {
        return new Intl.DateTimeFormat(locale, { ...options, timeZone: zone }).format(at);
      } catch {
        return new Intl.DateTimeFormat(locale, options).format(at);
      }
    };
    return {
      day: safe({ day: "numeric" }),
      month: safe({ month: "short" }).replace(".", ""),
      when: safe({ weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }),
    };
  };
}

/** Links to app pages do nothing in the settings' preview. */
export function usePreviewGuard() {
  const { preview } = useSite();
  return preview ? (event: MouseEvent) => event.preventDefault() : undefined;
}

/** «Events»: the box's events open to everyone. */
export function Events() {
  const { site, locale } = useSite();
  const { t } = useSiteText();
  const date = useEventDate();
  const guard = usePreviewGuard();
  if (site.events.length === 0) return null;
  return (
    <div className="evts" data-testid="site-events">
      {site.events.map((event) => {
        const when = date(event);
        return (
          <Link key={event.id} href={`/events/${event.id}`} className="evt" data-rv="up" onClick={guard}>
            <span className="dd">
              <b>{when.day}</b>
              <small>{when.month}</small>
            </span>
            <span>
              <b>{event.title}</b>
              <br />
              <span className="muted" style={{ fontSize: 13 }}>
                {when.when}
                {event.place_name ? ` · ${event.place_name}` : ""} · {event.price_cents > 0 ? money(event.price_cents, event.currency, locale) : t("free")}
              </span>
            </span>
          </Link>
        );
      })}
    </div>
  );
}

const PROGRAMME_ICONS: PhotoIcon[] = ["kb", "rings", "bar"];

/** «Προγράμματα»: programmes the box's coaches sell. */
export function Programmes() {
  const { site, locale } = useSite();
  const { t } = useSiteText();
  const guard = usePreviewGuard();
  if (site.programmes.length === 0) return null;
  return (
    <div className="prog2" data-testid="site-programmes">
      {site.programmes.map((programme, index) => {
        const body = (
          <>
            <Photo url={programme.cover_url} icon={PROGRAMME_ICONS[index % 3]} />
            <span className="b">
              <b>{programme.title}</b>
              {programme.summary || programme.weeks ? (
                <span className="muted" style={{ fontSize: 13 }}>
                  {[programme.weeks ? t("programmes.weeks", { count: programme.weeks }) : null, programme.summary].filter(Boolean).join(" · ")}
                </span>
              ) : null}
              {programme.price_cents ? <b className="acc">{money(programme.price_cents, programme.currency ?? "EUR", locale)}</b> : null}
            </span>
          </>
        );
        const style = { "--d": `${index * 90}ms` } as CSSProperties;
        return programme.url ? (
          <a key={programme.id} href={programme.url} data-rv="up" style={style} onClick={guard}>
            {body}
          </a>
        ) : (
          <div key={programme.id} data-rv="up" style={style}>
            {body}
          </div>
        );
      })}
    </div>
  );
}

/** «Αριθμοί κοινότητας» with their labels (aggregates only; zeros are left out). */
export function useStats() {
  const { site } = useSite();
  const { t } = useSiteText();
  return statEntries(site.stats).map((entry) => ({ ...entry, label: t(`stats.${entry.key}`, { count: entry.value }) }));
}

/** A number that counts up when seen (formatted for the page's language). */
export function CountUp({ value }: { value: number }) {
  const { locale } = useSite();
  return <span data-up={value}>{new Intl.NumberFormat(locale).format(value)}</span>;
}

/** The coaches' grid (the «Coaches» page). */
export function CoachGrid() {
  const { page } = useSite();
  const coaches = page.profile?.coaches ?? [];
  if (coaches.length === 0) return null;
  return (
    <div className="coachgrid" data-testid="site-coaches">
      {coaches.map((coach, index) => (
        <article key={coach.id} className="ld-pop" style={{ "--i": index } as CSSProperties}>
          <Photo url={coach.avatar_url} alt="" icon="person" />
          <h3>{coach.nickname || initials(coach.nickname)}</h3>
          {coach.class_types.length ? (
            <span className="muted" style={{ fontSize: 13 }}>
              {coach.class_types.join(" · ")}
            </span>
          ) : null}
        </article>
      ))}
    </div>
  );
}
