"use client";

import { useSyncExternalStore } from "react";

import { mapsSearchUrl, mapsUrl, readApple, serverApple, subscribeNever } from "@/lib/maps";

import { hoursSummary, mainLocation, openState } from "../site-data";
import { Photo, SVG_SLICE, useClock, useSite, useSiteText, type PhotoIcon } from "../site-context";

/** «Ανοιχτά · κλείνει 22:00»: in the browser only (it depends on the time). */
export function useOpenNow(): string | null {
  const { spans, site } = useSite();
  const { t } = useSiteText();
  const now = useClock(60_000);
  if (now === null) return null;
  const state = openState(spans, site.time_zone, now);
  if (!state) return null;
  switch (state.state) {
    case "open":
      return t("open.open", { time: state.until });
    case "opens":
      return t("open.opens", { time: state.at });
    case "closed":
      return t("open.closed");
    default:
      return t("open.closedToday");
  }
}

/** The open-now chip; keeps its place while the server renders. */
export function OpenNowChip({ className = "chip", style }: { className?: string; style?: React.CSSProperties }) {
  const text = useOpenNow();
  const { spans } = useSite();
  if (spans.length === 0) return null;
  return (
    <span className={className} style={{ ...style, visibility: text ? undefined : "hidden" }} data-testid="site-open-now">
      <span className="live" aria-hidden="true" />
      {text ?? " "}
    </span>
  );
}

/** Directions open in Apple Maps on Apple devices, Google Maps elsewhere. */
export function useDirections() {
  const { page } = useSite();
  const apple = useSyncExternalStore(subscribeNever, readApple, serverApple);
  const location = mainLocation(page);
  if (!location) return null;
  const address = [location.address, location.neighbourhood, location.city].filter(Boolean).join(", ");
  const href =
    location.latitude != null && location.longitude != null
      ? mapsUrl({ latitude: location.latitude, longitude: location.longitude }, page.box.name, apple)
      : mapsSearchUrl(`${page.box.name}, ${address}`, apple);
  return { location, address, href };
}

/** A drawn map (no tiles to load) with the pin, the address, the hours and directions. */
export function MapCard() {
  const { page, spans, locale } = useSite();
  const { t } = useSiteText();
  const directions = useDirections();
  if (!directions) return null;
  const hours = hoursSummary(spans, locale);
  return (
    <div data-testid="site-location">
      <div className="mapart">
        <svg viewBox="0 0 400 240" preserveAspectRatio={SVG_SLICE} aria-hidden="true">
          <rect width="400" height="240" fill="var(--s-surface)" />
          <g stroke="var(--s-line-strong)" strokeWidth="10" fill="none" strokeLinecap="round">
            <path d="M-10 70 L410 120" />
            <path d="M120 -10 L170 250" />
            <path d="M280 -10 L250 250" />
            <path d="M-10 190 L410 170" />
          </g>
          <g stroke="var(--s-line)" strokeWidth="4" fill="none">
            <path d="M-10 30 L410 60" />
            <path d="M60 -10 L80 250" />
            <path d="M340 -10 L330 250" />
            <path d="M-10 140 L410 150" />
            <path d="M200 -10 L215 250" />
          </g>
          <path d="M300 190 q40-30 90-10 v70 h-120z" fill="color-mix(in oklab,var(--s-ok) 25%,transparent)" />
        </svg>
        <span className="pin">{page.box.name}</span>
      </div>
      <div className="mapinfo">
        {directions.address ? <b>{directions.address}</b> : null}
        {hours ? <span className="muted">{hours}</span> : null}
        <a href={directions.href} target="_blank" rel="noopener noreferrer">
          {t("map.directions")}
        </a>
      </div>
    </div>
  );
}

const GALLERY_ICONS: PhotoIcon[] = ["bar", "kb", "rings", "person"];

/** «Φωτογραφίες»: a sideways strip; each photo opens the lightbox. */
export function Gallery() {
  const { gallery, open } = useSite();
  const { t } = useSiteText();
  if (gallery.length === 0) return null;
  return (
    <div className="gal" data-testid="site-gallery">
      {gallery.map((photo, index) => (
        <button
          key={photo.id}
          type="button"
          aria-label={t("gallery.open", { name: photo.caption || t("gallery.photo", { index: index + 1 }) })}
          onClick={() => open({ kind: "light", index })}
        >
          <Photo url={photo.url} caption={photo.caption} icon={GALLERY_ICONS[index % 4]} />
        </button>
      ))}
    </div>
  );
}
