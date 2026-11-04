"use client";

import type { CSSProperties } from "react";

import { aboutText, firstSentence, mainLocation } from "./site-data";
import { CtaButton, Lines, PageLink, Photo, useSite, useSiteText } from "./site-context";
import type { SitePage } from "./site-model";
import { SiteFrame } from "./SiteFrame";
import { HeroMedia } from "./widgets/hero-media";
import { InnerPage } from "./widgets/inner-page";
import { PackageStack } from "./widgets/packages";
import { MapCard, OpenNowChip } from "./widgets/place";
import { useNextClass } from "./widgets/schedule";
import { CountUp, Events, Faq, Programmes, useHeadlineRating, useStats } from "./widgets/social";
import { seenStories, useStories } from "./widgets/stories";

const TAB_ICONS: Record<SitePage, string> = { home: "⌂", schedule: "◷", packages: "€", coaches: "☺", space: "⌖" };
const delay = (ms: number) => ({ "--d": `${ms}ms` }) as CSSProperties;


/**
 * «Ιστορίες» (C): the phone's own language, for a young crowd. Story rings
 * from the open sections, full-height reels, a stack of package cards to
 * swipe, a countdown on the next-class reel and a tab bar at the bottom with
 * the main button in the middle. Every gesture has a button.
 */
export function StoriesTemplate() {
  const { page, pages, pageKey, cta, act, on } = useSite();
  const { t } = useSiteText();
  const header = (
    <header className="topC">
      <PageLink page="home" className="logo" aria-label={t("logoHome", { box: page.box.name })}>
        {page.box.name}
      </PageLink>
      {on("location") ? <OpenNowChip /> : null}
    </header>
  );
  const tab = (entry: (typeof pages)[number]) => (
    <PageLink key={entry.key} page={entry.key}>
      <b aria-hidden="true">{TAB_ICONS[entry.key]}</b>
      {t(`pages.${entry.label}`)}
    </PageLink>
  );
  const ctaTab =
    cta.kind === "none" ? null : cta.kind === "call" ? (
      <a className="cta" href={`tel:${(cta.phone ?? "").replace(/[^\d+]/g, "")}`} data-testid="site-tab-cta">
        <b aria-hidden="true">✆</b>
        {t("cta.tabCall")}
      </a>
    ) : (
      <button type="button" className="cta" onClick={() => act()} data-testid="site-tab-cta">
        <b aria-hidden="true">＋</b>
        {cta.kind === "trial" ? t("cta.tabTrial") : t("cta.tabContact")}
      </button>
    );
  const bars =
    pages.length > 1 || ctaTab ? (
      <nav className="tabs" aria-label={t("pagesNav")}>
        {pages.length > 1 ? pages.slice(0, 2).map(tab) : null}
        {ctaTab}
        {pages.length > 1 ? pages.slice(2).map(tab) : null}
      </nav>
    ) : null;
  return (
    <SiteFrame header={header} bars={bars} mainClassName="snap">
      {pageKey === "home" ? (
        <StoriesHome />
      ) : (
        <div className="wrapx" style={{ paddingTop: 8, paddingBottom: 100 }}>
          <InnerPage />
        </div>
      )}
    </SiteFrame>
  );
}

function StoriesHome() {
  const { page, site, on, open, pages } = useSite();
  const { t } = useSiteText();
  const stories = useStories();
  const next = useNextClass();
  const stats = useStats();
  const rating = useHeadlineRating();
  const about = aboutText(site, page);
  const place = mainLocation(page);
  const trial = on("trial_form");
  const spaceStory = stories.findIndex((story) => story.kind === "space");
  const reviewStory = stories.findIndex((story) => story.kind === "reviews");
  const hasSchedulePage = pages.some((entry) => entry.key === "schedule");

  return (
    <>
      {stories.length ? (
        <div className="rings" data-testid="site-stories">
          {stories.map((story, index) => (
            <button
              key={story.kind}
              type="button"
              className={`ring ld-pop ${seenStories.has(story.kind) ? "seen" : ""}`}
              style={{ "--i": index } as CSSProperties}
              onClick={() => open({ kind: "story", index })}
              aria-haspopup="dialog"
            >
              <span className="o" aria-hidden="true">
                <i>
                  {story.cover ? (
                    // eslint-disable-next-line @next/next/no-img-element -- media from the box's storage
                    <img src={story.cover} alt="" loading="lazy" />
                  ) : (
                    story.emoji
                  )}
                </i>
              </span>
              {story.name}
            </button>
          ))}
        </div>
      ) : null}
      <div className="reels">
        <section className="reel wide" data-testid="site-hero">
          <HeroMedia parallax={0.18} icon="kb" />
          <span className="eyebrow on-photo ld-fade">{page.box.name}</span>
          <h1 className="ld-go" style={{ margin: "8px 0 10px" }}>
            <Lines lines={trial ? [t("stories.trial1"), t("stories.trial2"), t("stories.trial3")] : [t("stories.hero1"), t("stories.hero2"), t("stories.hero3")]} />
          </h1>
          {about ? (
            <p className="ld-fade" style={{ ...delay(450), margin: "0 0 16px", maxWidth: "40ch" }}>
              {firstSentence(about)}
            </p>
          ) : null}
          <div className="ld-fade" style={{ ...delay(650), display: "flex", gap: 8, flexWrap: "wrap" }}>
            <CtaButton long />
            {spaceStory >= 0 ? (
              <button type="button" className="btn ghost on-photo" onClick={() => open({ kind: "story", index: spaceStory })}>
                {t("stories.seeSpace")}
              </button>
            ) : null}
          </div>
        </section>

        {on("schedule") && next ? (
          <section className="reel accent" data-rv="scale" data-testid="site-next-class">
            <span className="eyebrow">{t("next.title")}</span>
            <h2 style={{ margin: "6px 0" }}>
              {next.name} {next.when}
            </h2>
            <p className="count">{next.counter}</p>
            {hasSchedulePage ? (
              <p style={{ margin: "10px 0 0" }}>
                <PageLink page="schedule" className="btn" style={{ background: "var(--s-ink)", color: "var(--s-bg)" }}>
                  {t("stories.fullSchedule")}
                </PageLink>
              </p>
            ) : null}
          </section>
        ) : null}

        {on("packages") ? (
          <section className="reel solid" data-rv="scale">
            <span className="eyebrow">{t("pages.packages")}</span>
            <h2 style={{ margin: "6px 0 0" }}>{t("stories.swipe")}</h2>
            <PackageStack />
          </section>
        ) : null}

        {on("about") ? (
          <section className="reel" data-rv="scale" data-testid="site-about">
            <Photo url={null} icon="rings" parallax={0.15} />
            <span className="eyebrow on-photo">{t("stories.ourStory")}</span>
            <p style={{ margin: "8px 0 0", whiteSpace: "pre-line" }}>{about}</p>
          </section>
        ) : null}

        {on("stats") && stats.length ? (
          <section className="reel solid" data-rv="scale" data-testid="site-stats">
            <span className="eyebrow">{t("tiles.inNumbers")}</span>
            <div style={{ display: "grid", gridTemplateColumns: `repeat(${stats.length},1fr)`, gap: 10, marginTop: 10 }}>
              {stats.map((entry) => (
                <div key={entry.key}>
                  <b style={{ fontSize: 40, fontWeight: 900, display: "block", lineHeight: 1 }}>
                    <CountUp value={entry.value} />
                  </b>
                  <span className="muted" style={{ fontSize: 12 }}>
                    {entry.label}
                  </span>
                </div>
              ))}
            </div>
          </section>
        ) : null}

        {on("events") ? (
          <section className="reel solid" data-rv="scale">
            <span className="eyebrow">{t("sections.events")}</span>
            <div style={{ marginTop: 10 }}>
              <Events />
            </div>
          </section>
        ) : null}

        {on("programmes") ? (
          <section className="reel solid" data-rv="scale">
            <span className="eyebrow">{t("sections.programmes")}</span>
            <div style={{ marginTop: 10 }}>
              <Programmes />
            </div>
          </section>
        ) : null}

        {on("reviews") && rating ? (
          <section className="reel solid" data-rv="scale" data-testid="site-reviews">
            <span className="eyebrow">{t("sections.reviews")}</span>
            <h2 style={{ margin: "6px 0 10px" }}>
              <span className="stars" aria-hidden="true">★</span> {rating.text}
            </h2>
            {(site.reviews.palee?.latest ?? [])
              .filter((review) => review.body)
              .slice(0, 2)
              .map((review) => (
                <p key={review.id} style={{ margin: "0 0 10px" }}>
                  «{review.body}» {review.author_name ? <b>{review.author_name}</b> : null}
                </p>
              ))}
            {reviewStory >= 0 ? (
              <button type="button" className="btn ghost" onClick={() => open({ kind: "story", index: reviewStory })}>
                {t("stories.allReviews")}
              </button>
            ) : null}
          </section>
        ) : null}

        {on("location") && place ? (
          <section className="reel solid wide" data-rv="scale">
            <span className="eyebrow">{t("arena.findUs")}</span>
            <div style={{ marginTop: 10 }}>
              <MapCard />
            </div>
          </section>
        ) : null}

        {on("faq") ? (
          <section className="reel solid wide" data-rv="scale">
            <span className="eyebrow">{t("arena.questions")}</span>
            <Faq />
          </section>
        ) : null}
      </div>
      <div style={{ height: 30 }} />
    </>
  );
}
