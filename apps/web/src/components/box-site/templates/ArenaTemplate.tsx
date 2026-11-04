"use client";

import { useRef, useState, type CSSProperties } from "react";

import { aboutText, classTypes, firstSentence, mainLocation } from "./site-data";
import { CtaButton, Lines, PageLink, Photo, useSite, useSiteText } from "./site-context";
import { SiteFrame } from "./SiteFrame";
import { HeroMedia } from "./widgets/hero-media";
import { InnerPage } from "./widgets/inner-page";
import { MapCard } from "./widgets/place";
import { PackageCardsA } from "./widgets/packages";
import { useNextClass } from "./widgets/schedule";
import { CountUp, Faq, Programmes, Reviews, useEventDate, useStats } from "./widgets/social";

const delay = (ms: number) => ({ "--d": `${ms}ms` }) as CSSProperties;

/**
 * «Αρένα» (A): energy and huge condensed type, for CrossFit and functional
 * boxes. A title that rises line by line over a parallax photo, a countdown
 * to the next class, the WOD on a slanted band, numbers that count up, a
 * coaches carousel (swipe or ← →), a scroll progress bar, a full-screen menu
 * and the main button always in the thumb zone.
 */
export function ArenaTemplate() {
  const { page, pages, pageKey, open } = useSite();
  const { t } = useSiteText();
  const [first, ...rest] = page.box.name.trim().split(/\s+/);

  const header = (
    <header className="topA">
      <PageLink page="home" className="logo" aria-label={t("logoHome", { box: page.box.name })}>
        {rest.length ? (
          <span>
            {first} <b>{rest.join(" ")}</b>
          </span>
        ) : (
          <b>{first}</b>
        )}
      </PageLink>
      {pages.length > 1 ? (
        <nav className="navA" aria-label={t("pagesNav")}>
          {pages.map((entry) => (
            <PageLink key={entry.key} page={entry.key}>
              {t(`pages.${entry.label}`)}
            </PageLink>
          ))}
        </nav>
      ) : null}
      {pages.length > 1 ? (
        <button type="button" className="burger" aria-label={t("menu")} aria-haspopup="dialog" onClick={() => open({ kind: "menu" })} data-testid="site-menu-open">
          ☰
        </button>
      ) : null}
    </header>
  );

  const bars = (
    <>
      <div className="prog" data-prog aria-hidden="true" />
      <div className="stickyA">
        <CtaButton long testId="site-sticky-cta" />
      </div>
    </>
  );

  return (
    <SiteFrame header={header} bars={bars}>
      {pageKey === "home" ? <ArenaHome /> : <InnerPage />}
    </SiteFrame>
  );
}

function ArenaHome() {
  const { page, site, on, pages } = useSite();
  const { t } = useSiteText();
  const next = useNextClass();
  const stats = useStats();
  const eventDate = useEventDate();
  const carousel = useRef<HTMLDivElement>(null);
  const [marqueePaused, setMarqueePaused] = useState(false);
  const about = aboutText(site, page);
  const place = mainLocation(page);
  const where = place?.neighbourhood || place?.city || "";
  const coaches = page.profile?.coaches ?? [];
  const wod = site.wod[0];
  const hasPage = (key: string) => pages.some((entry) => entry.key === key);
  const types = classTypes(site.timetable);

  const why = [
    on("coaches") ? { title: t("why.coaches", { count: coaches.length }), text: [...new Set(coaches.flatMap((coach) => coach.class_types))].slice(0, 4).join(" · ") } : null,
    on("schedule") ? { title: t("why.classes", { count: site.timetable.length }), text: types.slice(0, 4).map((name) => site.class_type_names[name] ?? name).join(" · ") } : null,
    { title: t("why.progress"), text: t("why.progressText") },
  ].filter(Boolean) as { title: string; text: string }[];

  const scrollCoaches = (direction: number) => {
    const element = carousel.current;
    const card = element?.firstElementChild as HTMLElement | null;
    if (!element || !card || typeof element.scrollBy !== "function") return;
    element.scrollBy({ left: direction * (card.offsetWidth + 12) * (document.dir === "rtl" ? -1 : 1), behavior: "smooth" });
  };

  return (
    <>
      <section className="heroA" data-testid="site-hero">
        <HeroMedia parallax={0.25} icon="bar" />
        {next && on("schedule") ? (
          <PageLink page="schedule" className="nextclass ld-fade" style={delay(600)} data-testid="site-next-class">
            <span className="live" aria-hidden="true" />
            <span>{t("next.chip", { name: next.name, when: next.when })}</span>
            <b>{next.counter}</b>
          </PageLink>
        ) : null}
        <p className="who ld-fade">{[page.box.name, where].filter(Boolean).join(" · ")}</p>
        <h1 className="ld-go">
          <Lines lines={[t("arena.line1"), <em key="em">{t("arena.line2")}</em>, t("arena.line3")]} />
        </h1>
        {about ? (
          <p className="sub ld-fade" style={delay(500)}>
            {firstSentence(about)}
          </p>
        ) : null}
        <div className="ctas ld-fade" style={delay(700)}>
          <CtaButton />
          {hasPage("schedule") && on("schedule") ? (
            <PageLink page="schedule" className="btn ghost on-photo">
              {t("arena.seeSchedule")}
            </PageLink>
          ) : hasPage("packages") ? (
            <PageLink page="packages" className="btn ghost on-photo">
              {t("arena.seePrices")}
            </PageLink>
          ) : null}
        </div>
      </section>

      {on("wod") && wod ? (
        <div className={`marq ${marqueePaused ? "paused" : ""}`} data-testid="site-wod">
          <span className="lbl2">
            {t("wod.band", { title: wod.title })}{" "}
            <button type="button" className="marqbtn" aria-pressed={marqueePaused} aria-label={marqueePaused ? t("wod.play") : t("wod.pause")} onClick={() => setMarqueePaused(!marqueePaused)}>
              {marqueePaused ? "▶" : "❚❚"}
            </button>
          </span>
          <p className="sr">{[wod.title, wod.body].filter(Boolean).join(": ")}</p>
          <div className="track" aria-hidden="true">
            {[0, 1].flatMap((copy) =>
              [...(wod.body ?? "").split(/\n+/).filter(Boolean), wod.title].map((part, index) => <span key={`${copy}-${index}`}>{part} ✦</span>),
            )}
          </div>
        </div>
      ) : null}

      {on("stats") && stats.length ? (
        <section className="sec wrapx" aria-label={t("sections.stats")} data-testid="site-stats">
          <div className="stats">
            {stats.map((entry, index) => (
              <div key={entry.key} className="stat" data-rv="up" style={delay(index * 110)}>
                <b>
                  <CountUp value={entry.value} />
                </b>
                <span>{entry.label}</span>
              </div>
            ))}
          </div>
        </section>
      ) : null}

      {on("about") ? (
        <section className="sec wrapx" data-testid="site-about">
          <span className="eyebrow">{t("arena.whyEyebrow")}</span>
          <h2 className="big2" style={{ marginTop: 6 }} data-rv="lines">
            <Lines lines={[t("arena.why1"), t("arena.why2"), <span key="acc" className="acc">{t("arena.why3")}</span>]} />
          </h2>
          <p className="aboutA">{about}</p>
          <div className="why">
            {why.map((entry, index) => (
              <div key={entry.title} data-rv="left" style={delay(index * 120)}>
                <h3>{entry.title}</h3>
                {entry.text ? <p className="muted">{entry.text}</p> : null}
              </div>
            ))}
          </div>
        </section>
      ) : null}

      {on("coaches") ? (
        <section className="sec" data-testid="site-coaches">
          <div className="wrapx" style={{ display: "flex", justifyContent: "space-between", alignItems: "end", gap: 10 }}>
            <h2 className="h2A" data-rv="lines">
              <Lines lines={[t("arena.coaches")]} />
            </h2>
            {coaches.length > 1 ? (
              <div className="carobtns">
                <button type="button" onClick={() => scrollCoaches(-1)} aria-label={t("arena.prevCoach")}>
                  ←
                </button>
                <button type="button" onClick={() => scrollCoaches(1)} aria-label={t("arena.nextCoach")}>
                  →
                </button>
              </div>
            ) : null}
          </div>
          <div className="hscroll wrapx" ref={carousel} style={{ marginTop: 14 }}>
            {coaches.map((coach, index) => (
              <article key={coach.id} className="coachA" data-rv="scale" style={delay(index * 90)}>
                <Photo url={coach.avatar_url} icon="person" />
                <h3>{coach.nickname}</h3>
                {coach.class_types.length ? <span className="muted">{coach.class_types.join(" · ")}</span> : null}
              </article>
            ))}
          </div>
        </section>
      ) : null}

      {on("packages") ? (
        <section className="sec wrapx">
          <h2 className="h2A" data-rv="lines">
            <Lines lines={[t("arena.prices")]} />
          </h2>
          <p className="muted">{t("packages.sub")}</p>
          <div style={{ marginTop: 16 }}>
            <PackageCardsA limit={3} />
          </div>
          <p style={{ marginTop: 16 }}>
            <PageLink page="packages" className="btn ghost">
              {t("packages.all")}
            </PageLink>
          </p>
        </section>
      ) : null}

      {on("events") ? (
        <section className="sec wrapx" data-testid="site-events">
          <div style={{ display: "grid", gap: 12 }}>
            {site.events.slice(0, 3).map((event) => {
              const when = eventDate(event);
              return (
                <div key={event.id} className="eventA" data-rv="scale">
                  <span className="eyebrow" style={{ color: "rgba(255,255,255,.7)" }}>
                    {t("sections.events")}
                  </span>
                  <span className="date">
                    {when.day} {when.month}
                  </span>
                  <h3>{event.title}</h3>
                  <p style={{ opacity: 0.8 }}>{[when.when, event.place_name].filter(Boolean).join(" · ")}</p>
                </div>
              );
            })}
          </div>
        </section>
      ) : null}

      {on("programmes") ? (
        <section className="sec wrapx">
          <h2 className="h2A" data-rv="lines">
            <Lines lines={[t("sections.programmes")]} />
          </h2>
          <div style={{ marginTop: 14 }}>
            <Programmes />
          </div>
        </section>
      ) : null}

      {on("reviews") ? (
        <section className="sec wrapx">
          <h2 className="h2A" data-rv="lines">
            <Lines lines={[t("arena.reviews")]} />
          </h2>
          <Reviews />
        </section>
      ) : null}

      {on("location") ? (
        <section className="sec wrapx">
          <h2 className="h2A" data-rv="lines">
            <Lines lines={[t("arena.findUs")]} />
          </h2>
          <div style={{ marginTop: 14 }} data-rv="up">
            <MapCard />
          </div>
        </section>
      ) : null}

      {on("faq") ? (
        <section className="sec wrapx">
          <h2 className="h2A" data-rv="lines">
            <Lines lines={[t("arena.questions")]} />
          </h2>
          <Faq />
        </section>
      ) : null}
    </>
  );
}
