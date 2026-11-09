"use client";

import { useEffect, useReducer, useRef, type PointerEvent, type ReactNode } from "react";
import { useLocale } from "next-intl";

import { RTL_LOCALES, type AppLocale } from "@/i18n/locales";
import {
  HOLD_TO_PAUSE_MS,
  isPlaying,
  storyReducer,
  tapDirection,
} from "@/components/landing/story-player-state";

export type StoryFrameLabels = {
  carousel: string;
  pause: string;
  play: string;
  paused: string;
  previous: string;
  next: string;
  position: (current: number, total: number) => string;
};

/**
 * Full-screen stories for phones (ADR-555), shared by the guest landing and
 * the business landing (ADR-556). Tap the start third to go back and the
 * rest to go on; hold to pause and let go to carry on; the button pauses for
 * good. With reduced motion nothing moves on its own. `resetKey` starts over
 * from the first story when the content changes (the business audience).
 */
export function StoryFrame({
  count,
  renderSlide,
  brand,
  subheader,
  headerExtra,
  actions,
  labels,
  suspended = false,
  resetKey,
}: {
  count: number;
  renderSlide: (index: number) => ReactNode;
  brand: ReactNode;
  /** Shown centred under the header (the business landing's audience switch). */
  subheader?: ReactNode;
  headerExtra?: ReactNode;
  actions: ReactNode;
  labels: StoryFrameLabels;
  /** True while something covers the stories (the sign-in sheet): they wait. */
  suspended?: boolean;
  resetKey?: string;
}) {
  const rtl = RTL_LOCALES.has(useLocale() as AppLocale);
  const [state, dispatch] = useReducer(storyReducer(count), { index: 0, paused: false, holding: false });
  const holdTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const held = useRef(false);
  const playing = isPlaying(state) && !suspended;
  const index = Math.min(state.index, count - 1);

  useEffect(() => {
    dispatch({ type: "go", index: 0 });
  }, [resetKey]);

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
      aria-label={labels.carousel}
      className="landing-deep landing-glow flex min-h-[100dvh] flex-col px-4 pb-[max(1rem,env(safe-area-inset-bottom))] pt-[max(0.75rem,env(safe-area-inset-top))]"
      data-testid="landing-stories"
    >
      <ol className="flex gap-1" aria-hidden="true">
        {Array.from({ length: count }, (_, position) => (
          <li key={position} className="h-1 flex-1 overflow-hidden rounded-full" style={{ background: "color-mix(in srgb, var(--deep-contrast) 28%, transparent)" }}>
            {position < index ? (
              <span className="block h-full w-full" style={{ background: "var(--deep-contrast)" }} />
            ) : position === index ? (
              <span
                key={`${resetKey ?? ""}-${index}`}
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
        {brand}
        <div className="flex items-center gap-2">
          {headerExtra}
          {state.paused || state.holding ? (
            <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--spark)" }}>
              {labels.paused}
            </span>
          ) : null}
          <button
            type="button"
            onClick={() => dispatch({ type: "toggle" })}
            aria-label={state.paused ? labels.play : labels.pause}
            aria-pressed={state.paused}
            className="grid size-11 shrink-0 place-items-center rounded-full"
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
      {subheader ? <div className="mt-3 flex justify-center">{subheader}</div> : null}

      <div
        className="relative mt-5 flex flex-1 select-none flex-col justify-center [-webkit-touch-callout:none]"
        onPointerDown={onPointerDown}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerCancel}
        onPointerLeave={onPointerCancel}
        onContextMenu={(event) => event.preventDefault()}
        data-testid="landing-story-stage"
      >
        <div key={`${resetKey ?? ""}-${index}`} aria-live="polite" aria-atomic="true">
          <p className="sr-only">{labels.position(index + 1, count)}</p>
          {renderSlide(index)}
        </div>
      </div>

      <div className="sr-only">
        <button type="button" onClick={() => dispatch({ type: "previous" })}>{labels.previous}</button>
        <button type="button" onClick={() => dispatch({ type: "next" })}>{labels.next}</button>
      </div>

      <div className="mt-5 grid gap-2">{actions}</div>
    </section>
  );
}
