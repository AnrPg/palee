"use client";

import { useReducer, useRef, type PointerEvent, type ReactNode } from "react";
import { useLocale, useTranslations } from "next-intl";

import { PaleeMark } from "@/components/branding/PaleeMark";
import { PaleeTagline } from "@/components/branding/PaleeTagline";
import { RTL_LOCALES, type AppLocale } from "@/i18n/locales";
import {
  AutoVisual,
  BoxVisual,
  JournalVisual,
  PartnerVisual,
  PostVisual,
  ProgressVisual,
} from "@/components/landing/LandingVisuals";
import {
  HOLD_TO_PAUSE_MS,
  isPlaying,
  storyReducer,
  tapDirection,
} from "@/components/landing/story-player-state";

export const LANDING_PHOTO = "/landing-gym-floor.jpg";

const STORIES = ["hero", "crew", "journal", "progress", "partners", "box", "auto"] as const;
type Story = (typeof STORIES)[number];

const em = { em: (chunks: ReactNode) => <em>{chunks}</em> };

function StorySlide({ story }: { story: Story }) {
  const t = useTranslations("Landing");
  if (story === "hero") {
    return (
      <div className="grid gap-4">
        <PaleeTagline className="landing-rise text-base" accent="var(--spark)" />
        <h1 className="landing-rise landing-rise-1 landing-em text-4xl font-black leading-[1.05] tracking-tight">
          {t.rich("hero.title", em)}
        </h1>
        <p className="landing-rise landing-rise-2 landing-soft text-base">{t("hero.lede")}</p>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={LANDING_PHOTO} alt={t("photoAlt")} className="landing-rise landing-rise-2 aspect-[3/2] w-full rounded-2xl object-cover" />
      </div>
    );
  }
  const visual = {
    crew: <PostVisual />,
    journal: <JournalVisual />,
    progress: <ProgressVisual />,
    partners: <PartnerVisual />,
    box: <BoxVisual />,
    auto: <AutoVisual />,
  }[story];
  return (
    <div className="grid gap-4">
      <h2 className="landing-rise landing-em text-3xl font-black leading-[1.08] tracking-tight">
        {t.rich(`story.${story}Title`, em)}
      </h2>
      <p className="landing-rise landing-rise-1 landing-soft text-base">{t(`story.${story}Body`)}</p>
      <div className="landing-rise landing-rise-2">{visual}</div>
    </div>
  );
}

/**
 * Phones (ADR-555): Palee told in full-screen stories, like the ones people
 * already know. Tap the start third to go back and the rest to go on; hold to
 * pause and let go to carry on; the button pauses for good. With reduced
 * motion nothing moves on its own.
 */
export function StoryPlayer({
  onSignUp,
  onSignIn,
  suspended = false,
}: {
  onSignUp: () => void;
  onSignIn: () => void;
  /** True while the sign-in sheet covers the stories: they wait for it. */
  suspended?: boolean;
}) {
  const t = useTranslations("Landing");
  const rtl = RTL_LOCALES.has(useLocale() as AppLocale);
  const [state, dispatch] = useReducer(storyReducer(STORIES.length), { index: 0, paused: false, holding: false });
  const holdTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const held = useRef(false);
  const playing = isPlaying(state) && !suspended;

  const clearHold = () => {
    if (holdTimer.current) clearTimeout(holdTimer.current);
    holdTimer.current = null;
  };

  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0) return;
    held.current = false;
    clearHold();
    holdTimer.current = setTimeout(() => {
      held.current = true;
      dispatch({ type: "hold" });
    }, HOLD_TO_PAUSE_MS);
  };

  const onPointerUp = (event: PointerEvent<HTMLDivElement>) => {
    clearHold();
    if (held.current) {
      // Letting go after a hold only resumes; it never turns the page.
      held.current = false;
      dispatch({ type: "release" });
      return;
    }
    const box = event.currentTarget.getBoundingClientRect();
    dispatch({ type: tapDirection(event.clientX - box.left, box.width, rtl) });
  };

  const onPointerCancel = () => {
    clearHold();
    if (held.current) dispatch({ type: "release" });
    held.current = false;
  };

  return (
    <section
      aria-roledescription="carousel"
      aria-label={t("stories.label")}
      className="landing-deep flex min-h-[100dvh] flex-col px-4 pb-[max(1rem,env(safe-area-inset-bottom))] pt-[max(0.75rem,env(safe-area-inset-top))]"
      data-testid="landing-stories"
    >
      <ol className="flex gap-1" aria-hidden="true">
        {STORIES.map((story, position) => (
          <li key={story} className="h-1 flex-1 overflow-hidden rounded-full" style={{ background: "color-mix(in srgb, var(--deep-contrast) 28%, transparent)" }}>
            {position < state.index ? (
              <span className="block h-full w-full" style={{ background: "var(--deep-contrast)" }} />
            ) : position === state.index ? (
              <span
                key={state.index}
                className="landing-story-fill block h-full w-full"
                data-paused={playing ? "false" : "true"}
                style={{ background: "var(--deep-contrast)" }}
                onAnimationEnd={() => dispatch({ type: "next" })}
                data-testid="landing-story-bar"
              />
            ) : null}
          </li>
        ))}
      </ol>

      <header className="mt-3 flex items-center justify-between gap-3">
        <span className="flex items-center gap-2 text-lg font-black">
          <PaleeMark className="size-7 [&_path]:stroke-[var(--deep-contrast)]" />
          Palee
        </span>
        <div className="flex items-center gap-2">
          {state.paused || state.holding ? (
            <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--spark)" }}>
              {t("stories.paused")}
            </span>
          ) : null}
          <button
            type="button"
            onClick={() => dispatch({ type: "toggle" })}
            aria-label={state.paused ? t("stories.play") : t("stories.pause")}
            aria-pressed={state.paused}
            className="grid size-11 place-items-center rounded-full"
            style={{ background: "color-mix(in srgb, var(--deep-contrast) 14%, transparent)" }}
          >
            {state.paused ? (
              <svg viewBox="0 0 24 24" className="size-5" aria-hidden="true"><path d="M8 5v14l11-7z" fill="currentColor" /></svg>
            ) : (
              <svg viewBox="0 0 24 24" className="size-5" aria-hidden="true"><path d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z" fill="currentColor" /></svg>
            )}
          </button>
        </div>
      </header>

      <div
        className="relative mt-5 flex flex-1 select-none flex-col justify-center [-webkit-touch-callout:none]"
        onPointerDown={onPointerDown}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerCancel}
        onPointerLeave={onPointerCancel}
        onContextMenu={(event) => event.preventDefault()}
        data-testid="landing-story-stage"
      >
        <div key={state.index} aria-live="polite" aria-atomic="true">
          <p className="sr-only">{t("stories.position", { current: state.index + 1, total: STORIES.length })}</p>
          <StorySlide story={STORIES[state.index]} />
        </div>
      </div>

      <div className="sr-only">
        <button type="button" onClick={() => dispatch({ type: "previous" })}>{t("stories.previous")}</button>
        <button type="button" onClick={() => dispatch({ type: "next" })}>{t("stories.next")}</button>
      </div>

      <div className="mt-5 grid gap-2">
        <button
          type="button"
          onClick={onSignUp}
          className="min-h-12 rounded-full px-5 text-base font-extrabold"
          style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
        >
          {t("getStarted")}
        </button>
        <button
          type="button"
          onClick={onSignIn}
          className="min-h-12 rounded-full px-5 text-base font-bold"
          style={{ border: "1px solid color-mix(in srgb, var(--deep-contrast) 40%, transparent)" }}
        >
          {t("haveAccount")}
        </button>
      </div>
    </section>
  );
}
