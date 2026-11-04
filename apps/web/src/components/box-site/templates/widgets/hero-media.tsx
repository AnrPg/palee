"use client";

import { useRef, useState } from "react";

import { Photo, useSite, useSiteText, type PhotoIcon } from "../site-context";

/** The hero's picture: the box's video (muted, looping) or its cover, else the palette's gradient. */
export function useHeroPhoto() {
  const { page, gallery } = useSite();
  return page.profile?.cover?.url ?? gallery[0]?.url ?? null;
}

/**
 * The hero background. A video plays muted and loops, with a pause button
 * (WCAG 2.2.2); in calm mode only its poster shows.
 */
export function HeroMedia({ parallax, icon = "bar", className = "" }: { parallax?: number; icon?: PhotoIcon; className?: string }) {
  const { site, on, calm } = useSite();
  const { t } = useSiteText();
  const photo = useHeroPhoto();
  const video = on("photos") ? site.photos.video : null;
  const [paused, setPaused] = useState(false);
  const ref = useRef<HTMLVideoElement>(null);
  if (!video || calm)
    return <Photo url={video?.poster_url ?? photo} icon={icon} parallax={parallax} priority className={className} />;
  return (
    <>
      <div className={`ph has-img ${className}`} data-par={parallax}>
        <video ref={ref} src={video.url} poster={video.poster_url ?? photo ?? undefined} autoPlay muted loop playsInline preload="metadata" aria-hidden="true" />
      </div>
      <button
        type="button"
        className="roundbtn vidbtn"
        aria-pressed={paused}
        aria-label={paused ? t("video.play") : t("video.pause")}
        onClick={() => {
          const element = ref.current;
          if (!element) return;
          if (paused) void element.play().catch(() => undefined);
          else element.pause();
          setPaused(!paused);
        }}
      >
        {paused ? "▶" : "❚❚"}
      </button>
    </>
  );
}
