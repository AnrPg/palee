"use client";

import type { CSSProperties, ReactNode } from "react";

import { aboutText, classTypes, firstSentence, mainLocation } from "./site-data";
import { CtaButton, italic, Lines, PageLink, Photo, Stars, useSite, useSiteText, type PhotoIcon } from "./site-context";
import type { SitePage } from "./site-model";
import { SiteFrame } from "./SiteFrame";
import { HeroMedia } from "./widgets/hero-media";
import { InnerPage } from "./widgets/inner-page";
import { PackageMenu } from "./widgets/packages";
import { MapCard } from "./widgets/place";
import { CountUp, Faq, useEventDate, useHeadlineRating, useStats } from "./widgets/social";

const ROMAN = ["i", "ii", "iii"];
const delay = (ms: number) => ({ "--d": `${ms}ms` }) as CSSProperties;

/**
 * «Ατελιέ» (D): editorial and calm, for studios and premium boxes. Serif
 * titles with a light italic, an arched photo, words that light up as you
 * read, chapters that stack as you scroll, the page that turns dark for the
 * members' words, a coach's photo beside the cursor and a magnetic button.
 */
export function AtelierTemplate() {
  const { page, pageKey, open, pages } = useSite();
  const { t } = useSiteText();
  const header = (
    <header className="topD">
      <PageLink page="home" className="logo" aria-label={t("logoHome", { box: page.box.name })}>
        {page.box.name}
      </PageLink>
      <button type="button" className="menuBtn" aria-haspopup="dialog" onClick={() => open({ kind: "menu" })} data-testid="site-menu-open">
        {pages.length > 1 ? t("menu") : t("atelier.contact")} <i aria-hidden="true" />
      </button>
    </header>
  );
  return (
    <SiteFrame header={header}>
      {pageKey === "home" ? (
        <AtelierHome />
      ) : (
        <div className="pageD">
          <InnerPage />
        </div>
      )}
    </SiteFrame>
  );
}

type Chapter = { key: string; lab: string; title: ReactNode; text: string; photo: string | null; icon: PhotoIcon; link: { page: SitePage; label: string } | null };

function AtelierHome() {
  const { page, site, on, pages, gallery } = useSite();
  const { t } = useSiteText();
  const stats = useStats();
  const rating = useHeadlineRating();
  const eventDate = useEventDate();
  const about = aboutText(site, page);
  const place = mainLocation(page);
  const coaches = page.profile?.coaches ?? [];
  const types = classTypes(site.timetable).map((name) => site.class_type_names[name] ?? name);
  const wod = site.wod[0];
  const hasPage = (key: SitePage) => pages.some((entry) => entry.key === key);
  const review = (site.reviews.palee?.latest ?? []).find((entry) => entry.body);
  const event = site.events[0];

  const chapters: Chapter[] = [];
  if (on("schedule"))
    chapters.push({
      key: "schedule",
      lab: t("atelier.chapterClasses"),
      title: t.rich("atelier.classesTitle", { it: italic }),
      text: [t("why.classes", { count: site.timetable.length }), types.slice(0, 4).join(" · ")].filter(Boolean).join(". "),
      photo: gallery[0]?.url ?? null,
      icon: "bar",
      link: hasPage("schedule") ? { page: "schedule", label: t("atelier.seeWeek") } : null,
    });
  if (on("photos"))
    chapters.push({
      key: "space",
      lab: t("atelier.chapterSpace"),
      title: t.rich("atelier.spaceTitle", { it: italic }),
      text: gallery
        .map((photo) => photo.caption)
        .filter(Boolean)
        .slice(0, 4)
        .join(" · "),
      photo: gallery[1]?.url ?? gallery[0]?.url ?? null,
      icon: "kb",
      link: hasPage("space") ? { page: "space", label: t("atelier.comeIn") } : null,
    });
  if (on("programmes"))
    chapters.push({
      key: "programmes",
      lab: t("atelier.chapterHome"),
      title: t.rich("atelier.programmesTitle", { it: italic }),
      text: site.programmes.map((programme) => programme.title).join(" · "),
      photo: site.programmes.find((programme) => programme.cover_url)?.cover_url ?? null,
      icon: "rings",
      link: hasPage("schedule") ? { page: "schedule", label: t("atelier.seeProgrammes") } : null,
    });

  return (
    <>
      <section className="heroD" data-testid="site-hero">
        <div>
          <span className="lab ld-fade">{[place?.neighbourhood || place?.city, page.box.name].filter(Boolean).join(" · ")}</span>
          <h1 className="ld-go">
            <Lines lines={[t("atelier.hero1"), t.rich("atelier.hero2", { it: italic })]} />
          </h1>
          {about ? (
            <p className="sub ld-fade" style={delay(500)}>
              {firstSentence(about)}
            </p>
          ) : null}
          <div className="ctas ld-fade" style={delay(700)}>
            <CtaButton className="btnD magnet" long dot />
            {on("schedule") && hasPage("schedule") ? (
              <PageLink page="schedule" className="linkD">
                {t("atelier.theSchedule")}
              </PageLink>
            ) : null}
          </div>
        </div>
        <div className="arch ld-fade" style={delay(250)}>
          <HeroMedia parallax={0.12} icon="kb" />
        </div>
        <div className="cue" aria-hidden="true">
          <span className="lab">{t("atelier.scroll")}</span>
          <i />
        </div>
      </section>

      {on("schedule") && types.length ? (
        <div className="marqD" aria-hidden="true">
          <div className="track">
            {[...types, ...types].map((name, index) => (
              <span key={index} style={{ display: "contents" }}>
                <span>{name}</span>
                <span>✦</span>
              </span>
            ))}
          </div>
        </div>
      ) : null}

      {on("about") && about ? (
        <section className="sec wrapx" style={{ paddingBlock: 70 }} data-testid="site-about">
          <span className="lab">{t("atelier.philosophy")}</span>
          <p className="words" data-words style={{ margin: "14px 0 0" }}>
            {about
              .split(/\s+/)
              .filter(Boolean)
              .map((word, index) => (
                <span key={index}>{word} </span>
              ))}
          </p>
        </section>
      ) : null}

      {on("stats") && stats.length ? (
        <section className="wrapx" style={{ paddingBlock: "10px 40px" }} aria-label={t("sections.stats")} data-testid="site-stats">
          <div className="statsD">
            {stats.map((entry, index) => (
              <div key={entry.key} data-rv="up" style={delay(index * 120)}>
                <b>
                  <CountUp value={entry.value} />
                </b>
                <span className="lab" style={{ letterSpacing: ".12em" }}>
                  {entry.label}
                </span>
              </div>
            ))}
          </div>
        </section>
      ) : null}

      {chapters.length ? (
        <section style={{ paddingBlock: "20px 10px" }}>
          <div className="wrapx chap">
            <span className="lab">{t("atelier.chapters")}</span>
            <h2 className="h2D" data-rv="lines">
              <Lines lines={[t.rich("atelier.aDayHere", { it: italic })]} />
            </h2>
          </div>
          <div className="stackD">
            {chapters.map((chapter, index) => (
              <article key={chapter.key} style={{ "--k": index } as CSSProperties}>
                <span className="lab">
                  {ROMAN[index]} · {chapter.lab}
                </span>
                <h3>{chapter.title}</h3>
                {chapter.text ? (
                  <p className="muted" style={{ margin: 0 }}>
                    {chapter.text}
                  </p>
                ) : null}
                <Photo url={chapter.photo} icon={chapter.icon} />
                {chapter.link ? (
                  <PageLink page={chapter.link.page} className="linkD" style={{ justifySelf: "start" }}>
                    {chapter.link.label}
                  </PageLink>
                ) : null}
              </article>
            ))}
          </div>
        </section>
      ) : null}

      {on("wod") && wod ? (
        <section className="sec wrapx" data-testid="site-wod">
          <span className="lab">{[t("sections.wod"), wod.type].filter(Boolean).join(" · ")}</span>
          <h2 className="h2D" style={{ margin: "10px 0 14px" }} data-rv="lines">
            <Lines lines={[<span key="it" className="it">{wod.title}</span>]} />
          </h2>
          {wod.body ? (
            <p className="wodD" data-rv="up">
              {wod.body}
            </p>
          ) : null}
        </section>
      ) : null}

      {on("coaches") ? (
        <section className="sec wrapx" style={{ position: "relative" }} data-float-host data-testid="site-coaches">
          <span className="lab">{t("atelier.people")}</span>
          <h2 className="h2D" style={{ margin: "10px 0 18px" }} data-rv="lines">
            <Lines lines={[t.rich("atelier.onTheFloor", { it: italic })]} />
          </h2>
          {coaches.map((coach, index) => (
            <div key={coach.id} className="crow" data-float data-rv="up" style={delay(index * 80)}>
              <span className="av">
                <Photo url={coach.avatar_url} icon="person" />
              </span>
              <div>
                <h3>{coach.nickname}</h3>
                {coach.class_types.length ? (
                  <span className="muted" style={{ fontSize: 14 }}>
                    {coach.class_types.join(" · ")}
                  </span>
                ) : null}
              </div>
              <span />
            </div>
          ))}
          <div className="float" aria-hidden="true">
            <div className="ph has-img">
              {/* eslint-disable-next-line @next/next/no-img-element -- filled with the hovered coach's photo */}
              <img alt="" src={coaches.find((coach) => coach.avatar_url)?.avatar_url ?? undefined} />
            </div>
          </div>
        </section>
      ) : null}

      {on("packages") ? (
        <section className="sec wrapx">
          <span className="lab">{t("atelier.memberships")}</span>
          <h2 className="h2D" style={{ margin: "10px 0" }} data-rv="lines">
            <Lines lines={[t.rich("atelier.simplePrices", { it: italic })]} />
          </h2>
          <PackageMenu />
        </section>
      ) : null}

      {(on("reviews") && (review || rating)) || (on("events") && event) ? (
        <section className="night" data-night style={{ paddingBlock: 80 }}>
          {on("reviews") && (review || rating) ? (
            <div className="wrapx" data-testid="site-reviews">
              <span className="lab">{t("atelier.fromMembers")}</span>
              {review ? (
                <p className="quote" style={{ margin: "16px 0 12px" }} data-rv="up">
                  «{review.body}»
                </p>
              ) : null}
              {rating ? (
                <p className="lab">
                  {review?.author_name ? `${review.author_name} · ` : ""}
                  <Stars value={rating.value} /> {rating.text} · {t("reviews.count", { count: rating.count })}
                </p>
              ) : null}
            </div>
          ) : null}
          {on("events") && event ? (
            <div className="wrapx" style={{ marginTop: on("reviews") && (review || rating) ? 56 : 0 }} data-testid="site-events">
              {(() => {
                const when = eventDate(event);
                return (
                  <>
                    <span className="lab">
                      {t("sections.events")} · {when.day} {when.month}
                    </span>
                    <h3 style={{ fontSize: 40, fontWeight: 400, margin: "10px 0 6px" }} data-rv="up">
                      {event.title}
                    </h3>
                    <p className="muted" style={{ margin: 0 }}>
                      {[when.when, event.place_name].filter(Boolean).join(" · ")}
                    </p>
                  </>
                );
              })()}
            </div>
          ) : null}
        </section>
      ) : null}

      {on("faq") ? (
        <section className="sec wrapx">
          <span className="lab">{t("arena.questions")}</span>
          <div style={{ marginTop: 10 }}>
            <Faq />
          </div>
        </section>
      ) : null}

      {on("location") && place ? (
        <section className="sec wrapx">
          <span className="lab">{t("arena.findUs")}</span>
          <div style={{ marginTop: 14 }} data-rv="up">
            <MapCard />
          </div>
        </section>
      ) : null}

      <section className="wrapx closing">
        <span className="lab">{t("atelier.firstHour")}</span>
        <h2 data-rv="lines">
          <Lines lines={[t("atelier.closing1"), t.rich("atelier.closing2", { it: italic })]} />
        </h2>
        <CtaButton className="btnD magnet" long dot testId="site-closing-cta" />
      </section>
    </>
  );
}
