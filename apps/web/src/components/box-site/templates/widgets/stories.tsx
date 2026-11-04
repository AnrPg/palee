"use client";

import { useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import type { StoryKind } from "../site-data";
import { CtaButton, Photo, useSite, useSiteText, type PhotoIcon } from "../site-context";
import { OverlayShell } from "./overlays";
import { useEventDate } from "./social";

export type StorySlide = { title: string; text: string; photo: string | null; icon: PhotoIcon; cta?: boolean };
export type Story = { kind: StoryKind; name: string; emoji: string; cover: string | null; slides: StorySlide[] };

const EMOJI: Record<StoryKind, string> = { wod: "🔥", space: "🏠", coaches: "💪", events: "🏁", reviews: "⭐" };
const ICONS: PhotoIcon[] = ["bar", "kb", "rings", "person"];

/** The rings' stories, built from the visible sections («Ιστορίες»). */
export function useStories(): Story[] {
  const { stories, site, page, gallery } = useSite();
  const { t } = useSiteText();
  const tr = useTranslations("BoxReviews");
  const date = useEventDate();
  const list: Story[] = [];
  for (const kind of stories) {
    let slides: StorySlide[] = [];
    if (kind === "wod")
      slides = site.wod.map((wod, index) => ({ title: wod.title, text: wod.body ?? "", photo: null, icon: "bar", cta: index === site.wod.length - 1 }));
    if (kind === "space") slides = gallery.slice(0, 6).map((photo, index) => ({ title: photo.caption || t("pages.space"), text: "", photo: photo.url, icon: ICONS[index % 4]! }));
    if (kind === "coaches")
      slides = (page.profile?.coaches ?? []).map((coach) => ({ title: coach.nickname ?? "", text: coach.class_types.join(" · "), photo: coach.avatar_url ?? null, icon: "person" }));
    if (kind === "events")
      slides = site.events.map((event) => {
        const when = date(event);
        return { title: event.title, text: [when.when, event.place_name].filter(Boolean).join(" · "), photo: null, icon: "rings", cta: true };
      });
    if (kind === "reviews") {
      slides = (site.reviews.palee?.latest ?? [])
        .filter((review) => review.body)
        .map((review) => ({ title: `${"★".repeat(Math.round(review.rating))} ${review.author_name ?? tr("anonymous")}`, text: review.body ?? "", photo: null, icon: "person" }));
      if (slides.length === 0 && site.reviews.google?.rating)
        slides = [{ title: `★ ${site.reviews.google.rating}`, text: `${tr("fromGoogle")} · ${tr("googleCount", { count: site.reviews.google.count ?? 0 })}`, photo: null, icon: "person" }];
    }
    if (slides.length === 0) continue;
    list.push({ kind, name: t(`stories.names.${kind}`), emoji: EMOJI[kind], cover: slides.find((slide) => slide.photo)?.photo ?? null, slides });
  }
  return list;
}

/** Stories already watched on this visit (their ring turns grey). */
export const seenStories = new Set<StoryKind>();

const DURATION = 5000;

/**
 * One story full screen: progress bars, tap right or left (buttons), hold to
 * pause, swipe down to close, ← → keys, and a pause button (WCAG 2.2.2). In
 * calm mode nothing advances by itself.
 */
export function StoryViewer({ start }: { start: number }) {
  const { calm, close } = useSite();
  const { t } = useSiteText();
  const stories = useStories();
  const [storyIndex, setStoryIndex] = useState(Math.min(start, Math.max(0, stories.length - 1)));
  const [slide, setSlide] = useState(0);
  const [elapsed, setElapsed] = useState(0);
  const [paused, setPaused] = useState(false);
  const [holding, setHolding] = useState(false);
  const gesture = useRef<{ y: number; timer: number; held: boolean } | null>(null);
  const suppressClick = useRef(false);
  const story = stories[storyIndex];

  useEffect(() => {
    if (story) seenStories.add(story.kind);
  }, [story]);

  const step = (direction: number) => {
    if (!story) return;
    const next = slide + direction;
    setElapsed(0);
    if (next < 0) {
      setSlide(0);
      return;
    }
    if (next >= story.slides.length) {
      if (storyIndex + 1 < stories.length) {
        setStoryIndex(storyIndex + 1);
        setSlide(0);
      } else close();
      return;
    }
    setSlide(next);
  };
  const stepRef = useRef(step);
  useEffect(() => {
    stepRef.current = step;
  });

  const running = !paused && !holding && !calm;
  useEffect(() => {
    if (!running) return;
    const timer = window.setInterval(() => {
      setElapsed((value) => {
        if (value + 100 >= DURATION) {
          window.setTimeout(() => stepRef.current(1), 0);
          return 0;
        }
        return value + 100;
      });
    }, 100);
    return () => window.clearInterval(timer);
  }, [running, storyIndex, slide]);

  if (!story) return null;
  const current = story.slides[Math.min(slide, story.slides.length - 1)]!;

  return (
    <OverlayShell
      label={t("stories.label", { name: story.name })}
      onKeyDown={(event) => {
        if (event.key === "ArrowRight") step(1);
        if (event.key === "ArrowLeft") step(-1);
      }}
      testId="site-story"
    >
      <div
        className="story"
        onPointerDown={(event) => {
          if ((event.target as Element).closest(".head,.act")) return;
          const timer = window.setTimeout(() => {
            if (gesture.current) gesture.current.held = true;
            setHolding(true);
          }, 220);
          gesture.current = { y: event.clientY, timer, held: false };
        }}
        onPointerUp={(event) => {
          const current = gesture.current;
          gesture.current = null;
          setHolding(false);
          if (!current) return;
          window.clearTimeout(current.timer);
          suppressClick.current = current.held;
          if (event.clientY - current.y > 80) {
            suppressClick.current = true;
            close();
          }
        }}
        onPointerCancel={() => {
          if (gesture.current) window.clearTimeout(gesture.current.timer);
          gesture.current = null;
          setHolding(false);
        }}
      >
        <div className="bars" aria-hidden="true">
          {story.slides.map((_, index) => (
            <i key={index}>
              <b style={{ width: index < slide ? "100%" : index === slide ? `${Math.min(100, (elapsed / DURATION) * 100)}%` : "0%" }} />
            </i>
          ))}
        </div>
        <div className="head">
          <span>
            {story.emoji} {story.name}
          </span>
          <span className="sp" />
          <button type="button" onClick={() => setPaused((value) => !value)} aria-label={paused ? t("stories.resume") : t("stories.pause")} aria-pressed={paused} data-testid="site-story-pause">
            {paused ? "▶" : "❚❚"}
          </button>
          <button type="button" onClick={close} aria-label={t("close")} data-dialog-close>
            ✕
          </button>
        </div>
        <div className="slide" key={`${storyIndex}-${slide}`} aria-live="polite">
          <Photo url={current.photo} icon={current.icon} priority />
          <h3>{current.title}</h3>
          {current.text ? <p className="txt">{current.text}</p> : null}
          {current.cta ? (
            <div className="act">
              <CtaButton long choice={story.kind === "events" ? current.title : ""} />
            </div>
          ) : null}
          <p className="hintS">{t("stories.hint")}</p>
        </div>
        <button
          type="button"
          className="zone l"
          aria-label={t("stories.prev")}
          onClick={() => {
            if (suppressClick.current) {
              suppressClick.current = false;
              return;
            }
            step(-1);
          }}
        />
        <button
          type="button"
          className="zone r"
          aria-label={t("stories.next")}
          onClick={() => {
            if (suppressClick.current) {
              suppressClick.current = false;
              return;
            }
            step(1);
          }}
        />
      </div>
    </OverlayShell>
  );
}
