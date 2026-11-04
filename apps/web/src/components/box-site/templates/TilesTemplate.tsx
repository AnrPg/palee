"use client";

import type { CSSProperties, MouseEvent, ReactNode } from "react";
import { flushSync } from "react-dom";

import { aboutText, balanceTiles, cheapestPackage, cheapestProgramme, firstSentence, heroSpansAll, initials, mainLocation, scheduleDays } from "./site-data";
import { CtaButton, Lines, money, PageLink, Photo, useClock, usePeriodLabel, useSite, useSiteText, withViewTransition, type TileKey } from "./site-context";
import { SiteFrame } from "./SiteFrame";
import { HeroMedia } from "./widgets/hero-media";
import { InnerPage } from "./widgets/inner-page";
import { OverlayShell } from "./widgets/overlays";
import { OpenNowChip, useOpenNow } from "./widgets/place";
import { Schedule, useNextClass } from "./widgets/schedule";
import { Events, Faq, Programmes, Reviews, useHeadlineRating, useStats } from "./widgets/social";

type Tile = { key: string; wide: boolean; node: (className: string, style: CSSProperties) => ReactNode };

/**
 * «Πλακίδια» (B): a calm grid of live tiles that works for every box. Tiles
 * come in one after another, the hero photo zooms slowly, a tile grows into
 * its own page (View Transitions), the WOD tile shines and tiles tilt under
 * a mouse. Tiles share out again when sections are switched off, without
 * holes on the phone's two columns.
 */
export function TilesTemplate() {
  const { page, pages, pageKey } = useSite();
  const { t } = useSiteText();
  const header = (
    <header className="topB">
      <PageLink page="home" className="logo" aria-label={t("logoHome", { box: page.box.name })}>
        {page.box.logo_url ? (
          // eslint-disable-next-line @next/next/no-img-element -- the box's logo
          <img src={page.box.logo_url} alt="" />
        ) : (
          <i aria-hidden="true" />
        )}
        <span>{page.box.name}</span>
      </PageLink>
      <CtaButton />
    </header>
  );
  const bars =
    pages.length > 1 ? (
      <nav className={`navB ${pages.length > 3 ? "many" : ""}`} aria-label={t("pagesNav")}>
        {pages.map((entry) => (
          <PageLink key={entry.key} page={entry.key}>
            {t(`pages.${entry.label}`)}
          </PageLink>
        ))}
      </nav>
    ) : null;
  return (
    <SiteFrame header={header} bars={bars}>
      {pageKey === "home" ? (
        <TilesHome />
      ) : (
        <div className="pageB">
          <InnerPage />
        </div>
      )}
    </SiteFrame>
  );
}

function TilesHome() {
  const { page, site, on, open, calm, gallery, packages, locale, act } = useSite();
  const { t } = useSiteText();
  const next = useNextClass();
  const openNow = useOpenNow();
  const stats = useStats();
  const rating = useHeadlineRating();
  const per = usePeriodLabel();
  const now = useClock(60_000);
  const coaches = page.profile?.coaches ?? [];
  const place = mainLocation(page);
  const wod = site.wod[0];
  const tiles: Tile[] = [];

  const grow = (tile: TileKey) => (event: MouseEvent<HTMLButtonElement>) => {
    const element = event.currentTarget;
    element.style.setProperty("view-transition-name", "bw-tile");
    withViewTransition(calm, () => {
      element.style.removeProperty("view-transition-name");
      flushSync(() => open({ kind: "tile", tile }));
    });
  };
  const button = (tile: TileKey, testId: string, extra: string, inner: ReactNode) => (className: string, style: CSSProperties) => (
    <button type="button" className={`${className} ${extra}`} style={style} onClick={grow(tile)} data-tilt data-testid={testId}>
      {inner}
    </button>
  );
  const link = (target: "schedule" | "packages" | "coaches" | "space", testId: string, inner: ReactNode) => (className: string, style: CSSProperties) => (
    <PageLink page={target} className={className} style={style} data-tilt data-testid={testId}>
      {inner}
    </PageLink>
  );

  if (on("schedule") && next)
    tiles.push({
      key: "next",
      wide: false,
      node: button(
        "next",
        "site-next-class",
        "acc",
        <>
          <span className="k">{t("next.title")}</span>
          <span className="v">
            {next.name}
            <br />
            {next.when}
          </span>
          <span style={{ fontVariantNumeric: "tabular-nums", fontWeight: 700, minHeight: "1.5em" }}>{next.counter}</span>
          <span className="go" aria-hidden="true">↗</span>
        </>,
      ),
    });
  if (on("wod") && wod)
    tiles.push({
      key: "wod",
      wide: false,
      node: button(
        "wod",
        "site-wod",
        "ink",
        <>
          <span className="k">{t("sections.wod")}</span>
          <span className="v">{wod.title}</span>
          {wod.body ? <span style={{ fontSize: 13, opacity: 0.8 }}>{firstSentence(wod.body.split(/\n/)[0], 60)}</span> : null}
          <span className="go" aria-hidden="true">↗</span>
        </>,
      ),
    });
  if (on("schedule") && next) {
    const days = scheduleDays(site.timetable, site.time_zone, locale, site.class_type_names, now);
    const day = days.find((entry) => entry.entries.some((item) => item.id === next.id));
    const list = (day?.entries ?? []).filter((item) => item.startsAt >= next.startsAt).slice(0, 3);
    tiles.push({
      key: "today",
      wide: true,
      node: link(
        "schedule",
        "site-today",
        <>
          <span className="k">{next.dayOffset === 0 ? t("tiles.today") : t("tiles.nextDay")}</span>
          <span className="mini">
            {list.map((item) => (
              <span key={item.id} style={{ display: "flex" }}>
                <b>{item.time}</b>
                <span>{item.name}</span>
                <span className="muted">{t("schedule.minutes", { count: item.minutes })}</span>
              </span>
            ))}
          </span>
          <span className="go" aria-hidden="true">→</span>
        </>,
      ),
    });
  }
  const cheapest = cheapestPackage(packages);
  if (on("packages"))
    tiles.push({
      key: "packages",
      wide: false,
      node: link(
        "packages",
        "site-packages-tile",
        <>
          <span className="k">{t("pages.packages")}</span>
          <span className="v">
            {cheapest ? t("from", { price: money(cheapest.base_price_cents, cheapest.currency, locale) }) : t("packages.title")}
            {cheapest && per(cheapest.billing_period) ? (
              <>
                <br />
                <span className="muted" style={{ fontSize: 14, fontWeight: 600 }}>
                  {per(cheapest.billing_period)}
                </span>
              </>
            ) : null}
          </span>
          <span className="go" aria-hidden="true">→</span>
        </>,
      ),
    });
  if (on("reviews") && rating)
    tiles.push({
      key: "reviews",
      wide: false,
      node: button(
        "reviews",
        "site-reviews-tile",
        "",
        <>
          <span className="k">{t("sections.reviews")}</span>
          <span className="v">
            <span className="stars" aria-hidden="true">★</span> {rating.text}
          </span>
          <span className="muted" style={{ fontSize: 12 }}>
            {t("reviews.count", { count: rating.count })}
          </span>
          <span className="go" aria-hidden="true">↗</span>
        </>,
      ),
    });
  if (on("about"))
    tiles.push({
      key: "about",
      wide: true,
      node: button(
        "about",
        "site-about",
        "",
        <>
          <span className="k">{t("tiles.whoWeAre")}</span>
          <span style={{ fontSize: 16, fontWeight: 600 }}>{firstSentence(aboutText(site, page))}</span>
          <span className="go" aria-hidden="true">↗</span>
        </>,
      ),
    });
  if (on("coaches"))
    tiles.push({
      key: "coaches",
      wide: true,
      node: link(
        "coaches",
        "site-coaches",
        <>
          <span className="k">{t("tiles.team")}</span>
          <span className="faces" aria-hidden="true">
            {coaches.slice(0, 6).map((coach) => (
              <i key={coach.id}>
                {coach.avatar_url ? (
                  // eslint-disable-next-line @next/next/no-img-element -- media from the box's storage
                  <img src={coach.avatar_url} alt="" loading="lazy" />
                ) : (
                  initials(coach.nickname)
                )}
              </i>
            ))}
          </span>
          <span style={{ fontWeight: 700 }}>
            {[t("why.coaches", { count: coaches.length }), [...new Set(coaches.flatMap((coach) => coach.class_types))].slice(0, 3).join(", ")].filter(Boolean).join(" · ")}
          </span>
          <span className="go" aria-hidden="true">→</span>
        </>,
      ),
    });
  if (on("stats") && stats.length)
    tiles.push({
      key: "stats",
      wide: false,
      node: (className, style) => (
        <div className={className} style={style} data-testid="site-stats">
          <span className="k">{t("tiles.inNumbers")}</span>
          <span className="v">
            <span data-up={stats[0]!.value}>{new Intl.NumberFormat(locale).format(stats[0]!.value)}</span>
            <br />
            <span style={{ fontSize: 14, fontWeight: 600 }}>{stats[0]!.label}</span>
          </span>
          {stats.slice(1).map((entry) => (
            <span key={entry.key} className="muted" style={{ fontSize: 12 }}>
              {new Intl.NumberFormat(locale).format(entry.value)} {entry.label}
            </span>
          ))}
        </div>
      ),
    });
  if (on("photos") && gallery.length)
    tiles.push({
      key: "photos",
      wide: false,
      node: link(
        "space",
        "site-photos",
        <>
          <span className="k">{t("pages.space")}</span>
          <span className="thumbs" aria-hidden="true">
            {gallery.slice(0, 6).map((photo) => (
              <Photo key={photo.id} url={photo.url} icon={null} />
            ))}
          </span>
          <span className="go" aria-hidden="true">→</span>
        </>,
      ),
    });
  if (on("location") && place)
    tiles.push({
      key: "location",
      wide: true,
      node: link(
        "space",
        "site-location",
        <>
          <svg className="mapmini" viewBox="0 0 400 200" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
            <rect width="400" height="200" fill="var(--s-surface)" />
            <g stroke="var(--s-line-strong)" strokeWidth="9" fill="none">
              <path d="M-10 60 L410 110" />
              <path d="M150 -10 L190 210" />
              <path d="M300 -10 L280 210" />
            </g>
            <circle cx="200" cy="95" r="12" fill="var(--s-accent)" />
            <circle cx="200" cy="95" r="26" fill="none" stroke="var(--s-accent)" strokeWidth="2" opacity=".5" />
          </svg>
          <span className="k over">
            {openNow ? (
              <>
                <span className="live" aria-hidden="true" />
                {openNow}
              </>
            ) : (
              t("sections.location")
            )}
          </span>
          <span className="v sm over">{[place.address, place.neighbourhood || place.city].filter(Boolean).join(", ")}</span>
          <span className="go" aria-hidden="true">→</span>
        </>,
      ),
    });
  if (on("events") && site.events[0])
    tiles.push({
      key: "events",
      wide: false,
      node: button(
        "event",
        "site-events",
        "",
        <>
          <span className="k">{t("sections.events")}</span>
          <span className="v sm">{site.events[0].title}</span>
          {site.events.length > 1 ? (
            <span className="muted" style={{ fontSize: 12 }}>
              {t("tiles.moreEvents", { count: site.events.length - 1 })}
            </span>
          ) : null}
          <span className="go" aria-hidden="true">↗</span>
        </>,
      ),
    });
  if (on("programmes")) {
    const cheapestOne = cheapestProgramme(site.programmes);
    tiles.push({
      key: "programmes",
      wide: false,
      node: button(
        "programmes",
        "site-programmes",
        "",
        <>
          <span className="k">{t("sections.programmes")}</span>
          <span className="v sm">{t("tiles.programmes", { count: site.programmes.length })}</span>
          {cheapestOne ? (
            <span className="muted" style={{ fontSize: 12 }}>
              {t("from", { price: money(cheapestOne.price_cents ?? 0, cheapestOne.currency ?? "EUR", locale) })}
            </span>
          ) : null}
          <span className="go" aria-hidden="true">↗</span>
        </>,
      ),
    });
  }
  if (on("faq") && site.faq[0])
    tiles.push({
      key: "faq",
      wide: false,
      node: button(
        "faq",
        "site-faq",
        "",
        <>
          <span className="k">{t("arena.questions")}</span>
          <span className="v sm">{site.faq[0].question}</span>
          {site.faq.length > 1 ? (
            <span className="muted" style={{ fontSize: 12 }}>
              {t("tiles.moreQuestions", { count: site.faq.length - 1 })}
            </span>
          ) : null}
          <span className="go" aria-hidden="true">↗</span>
        </>,
      ),
    });
  if (on("contact_form") && on("trial_form"))
    tiles.push({
      key: "contact",
      wide: false,
      node: (className, style) => (
        <button type="button" className={`${className} acc`} style={style} onClick={() => act("", "contact")} data-tilt data-testid="site-contact-tile">
          <span className="k">{t("tiles.askUs")}</span>
          <span className="v sm">{t("cta.contact")}</span>
          <span className="go" aria-hidden="true">↗</span>
        </button>
      ),
    });

  const shown = balanceTiles(tiles);
  return (
    <div className="bento" data-testid="site-bento">
      <div className={`tile hero ${heroSpansAll(shown.length) ? "full" : ""}`} data-testid="site-hero">
        <HeroMedia icon="kb" />
        <div className="in2">
          <OpenNowChip className="chip on-photo ld-fade" style={{ width: "max-content", marginBottom: 10 }} />
          <h1 className="ld-go">
            <Lines lines={[t("tiles.hero1"), t("tiles.hero2")]} />
          </h1>
          <p className="who ld-fade" style={{ "--d": "400ms" } as CSSProperties}>
            {[page.box.name, place?.neighbourhood || place?.city].filter(Boolean).join(" · ")}
          </p>
        </div>
      </div>
      {shown.map((tile, index) => (
        <TileSlot key={tile.key} tile={tile} index={index} />
      ))}
    </div>
  );
}

function TileSlot({ tile, index }: { tile: Tile; index: number }) {
  return <>{tile.node(`tile ld-pop ${tile.wide ? "w2" : ""}`, { "--i": index + 1 } as CSSProperties)}</>;
}

/** A tile grown into its page (the layer over the grid). */
export function TileDetail({ tile }: { tile: TileKey }) {
  const { site, page, close } = useSite();
  const { t } = useSiteText();
  const wod = site.wod[0];
  const titles: Record<TileKey, string> = {
    next: t("schedule.title"),
    wod: wod?.title ?? t("sections.wod"),
    reviews: t("sections.reviews"),
    event: t("sections.events"),
    programmes: t("sections.programmes"),
    about: t("tiles.whoWeAre"),
    faq: t("sections.faq"),
  };
  return (
    <OverlayShell label={titles[tile]} testId="site-tile-detail">
      <div className="detail" style={{ viewTransitionName: "bw-tile" } as CSSProperties}>
        <button type="button" className="x" onClick={close} aria-label={t("close")} data-dialog-close>
          ✕
        </button>
        <div className="inner">
          <h2>{titles[tile]}</h2>
          {tile === "next" ? <Schedule /> : null}
          {tile === "wod"
            ? site.wod.map((entry) => (
                <div key={entry.id}>
                  {entry.type ? <span className="chip">{entry.type}</span> : null}
                  {entry.body ? <div className="wod">{entry.body}</div> : null}
                </div>
              ))
            : null}
          {tile === "reviews" ? <Reviews /> : null}
          {tile === "event" ? <Events /> : null}
          {tile === "programmes" ? <Programmes /> : null}
          {tile === "about" ? <p style={{ fontSize: 18, whiteSpace: "pre-line" }}>{aboutText(site, page)}</p> : null}
          {tile === "faq" ? <Faq /> : null}
          {tile === "wod" || tile === "event" ? (
            <p style={{ marginTop: 16 }}>
              <CtaButton choice={tile === "wod" ? `WOD ${wod?.title ?? ""}` : ""} />
            </p>
          ) : null}
        </div>
      </div>
    </OverlayShell>
  );
}
