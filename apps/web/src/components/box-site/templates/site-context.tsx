"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { createContext, useContext, useSyncExternalStore, type CSSProperties, type MouseEvent, type ReactNode, type RefObject } from "react";
import { flushSync } from "react-dom";
import { useTranslations } from "next-intl";

import type { PublicSiteV2 } from "@/api/box-site";
import type { PublicPackage } from "@/api/my-payments";
import type { PublicBoxPage } from "@/api/social";
import type { SiteLanguage } from "@/lib/public-site";

import type { TemplateKey } from "./palettes";
import type { GalleryPhoto, OpeningSpan, StoryKind } from "./site-data";
import { sitePagePath, type SiteCta, type SitePage, type SitePageEntry } from "./site-model";

/** What a template can open over the page. */
export type Overlay =
  | { kind: "form"; form: "trial" | "contact"; choice: string }
  | { kind: "menu" }
  | { kind: "languages" }
  | { kind: "light"; index: number }
  | { kind: "story"; index: number }
  | { kind: "tile"; tile: TileKey };

export type TileKey = "next" | "wod" | "reviews" | "event" | "programmes" | "about" | "faq";

export type SiteCtx = {
  page: PublicBoxPage;
  site: PublicSiteV2;
  template: TemplateKey;
  packages: PublicPackage[];
  onlinePayments: boolean;
  visible: readonly string[];
  on: (section: string) => boolean;
  pages: SitePageEntry[];
  pageKey: SitePage;
  /** The site's base in this language: `/b/<slug>`, `/b/<slug>/en`, "" or "/en" on the box's domain. */
  base: string;
  /** The site's base in the box's own language (privacy, language links). */
  rootBase: string;
  language: SiteLanguage;
  /** The language of the page's content (`lang`). */
  contentLanguage: string;
  locale: string;
  standalone: boolean;
  preview: boolean;
  calm: boolean;
  cta: SiteCta;
  gallery: GalleryPhoto[];
  spans: OpeningSpan[];
  stories: StoryKind[];
  siteRef: RefObject<HTMLDivElement | null>;
  open: (overlay: Overlay) => void;
  close: () => void;
  overlay: Overlay | null;
  navigate: (page: SitePage) => void;
  act: (choice?: string, kind?: "trial" | "contact") => void;
};

const Ctx = createContext<SiteCtx | null>(null);
export const SiteProvider = Ctx.Provider;

export function useSite(): SiteCtx {
  const value = useContext(Ctx);
  if (!value) throw new Error("useSite:no-BoxWebsite");
  return value;
}

/** The website's own strings (ADR-530) and the shared website strings (ADR-352). */
export function useSiteText() {
  return { t: useTranslations("SiteTemplates"), tb: useTranslations("BoxSite") };
}

// ── Time ────────────────────────────────────────────────────────────────────

const clocks = new Map<number, { subscribe: (notify: () => void) => () => void; read: () => number }>();

function clock(step: number) {
  let entry = clocks.get(step);
  if (!entry) {
    entry = {
      subscribe: (notify) => {
        const timer = window.setInterval(notify, Math.min(step, 1000));
        return () => window.clearInterval(timer);
      },
      read: () => Math.floor(Date.now() / step) * step,
    };
    clocks.set(step, entry);
  }
  return entry;
}

const serverNow = () => null;

/**
 * The time, to `step` ms, in the browser only: null while the server renders
 * and while the page hydrates, so time-dependent text never mismatches.
 */
export function useClock(step = 1000): number | null {
  const entry = clock(step);
  return useSyncExternalStore<number | null>(entry.subscribe, entry.read, serverNow);
}

// ── Navigation ─────────────────────────────────────────────────────────────

let pendingTransition: (() => void) | null = null;

/** Ends a page change's View Transition once the new page rendered. */
export function settlePageTransition() {
  pendingTransition?.();
  pendingTransition = null;
}

type ViewTransitionDocument = Document & { startViewTransition?: (update: () => void | Promise<void>) => unknown };

/** Runs a DOM update inside a View Transition when the browser has them and motion is on. */
export function withViewTransition(calm: boolean, update: () => void | Promise<void>) {
  const doc = document as ViewTransitionDocument;
  if (calm || !doc.startViewTransition || window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) {
    void update();
    return;
  }
  doc.startViewTransition.call(doc, update);
}

/** Page changes for the website: real URLs, or the preview's callback. */
export function usePageNavigation(base: string, preview: { onNavigate: (page: SitePage) => void } | undefined, calm: boolean) {
  const router = useRouter();
  return (page: SitePage) => {
    if (preview) {
      withViewTransition(calm, () => flushSync(() => preview.onNavigate(page)));
      return;
    }
    const href = sitePagePath(base, page);
    withViewTransition(
      calm,
      () =>
        new Promise<void>((resolve) => {
          pendingTransition = resolve;
          window.setTimeout(settlePageTransition, 1200);
          router.push(href);
        }),
    );
  };
}

/**
 * A link to one of the site's pages: a real link (search engines follow it),
 * which in the preview switches the preview's page instead.
 */
export function PageLink({
  page,
  className,
  style,
  children,
  onNavigate,
  ...rest
}: {
  page: SitePage;
  className?: string;
  style?: CSSProperties;
  children: ReactNode;
  onNavigate?: () => void;
  "aria-label"?: string;
  "data-testid"?: string;
  "data-rv"?: string;
  "data-tilt"?: boolean;
}) {
  const { base, pageKey, navigate, calm } = useSite();
  const href = sitePagePath(base, page);
  function click(event: MouseEvent<HTMLAnchorElement>) {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    onNavigate?.();
    if (page === pageKey) {
      window.scrollTo({ top: 0, behavior: calm ? "auto" : "smooth" });
      return;
    }
    navigate(page);
  }
  return (
    <Link href={href} className={className} style={style} aria-current={page === pageKey ? "page" : undefined} onClick={click} scroll {...rest}>
      {children}
    </Link>
  );
}

/** The one main button: trial form, else contact form, else a call. Nothing when the box has none of them. */
export function CtaButton({
  className = "btn",
  long = false,
  choice = "",
  dot = false,
  testId,
  style,
}: {
  className?: string;
  long?: boolean;
  choice?: string;
  dot?: boolean;
  testId?: string;
  style?: CSSProperties;
}) {
  const { cta, act } = useSite();
  const { t } = useSiteText();
  if (cta.kind === "none") return null;
  const label =
    cta.kind === "trial" ? t(long ? "cta.trialLong" : "cta.trial") : cta.kind === "contact" ? t("cta.contact") : t("cta.call", { phone: cta.phone ?? "" });
  const inner = (
    <>
      {dot ? <span className="dot" aria-hidden="true" /> : null}
      {label}
    </>
  );
  if (cta.kind === "call")
    return (
      <a href={`tel:${(cta.phone ?? "").replace(/[^\d+]/g, "")}`} className={className} style={style} data-testid={testId ?? "site-cta"}>
        {inner}
      </a>
    );
  return (
    <button type="button" className={className} style={style} onClick={() => act(choice)} data-testid={testId ?? "site-cta"}>
      {inner}
    </button>
  );
}

/** A title that rises line by line («ln»): each line clips its own text. */
export function Lines({ lines }: { lines: ReactNode[] }) {
  return (
    <>
      {lines.map((line, index) => (
        <span key={index} className="ln" style={{ "--i": index } as CSSProperties}>
          <span>{line}</span>
        </span>
      ))}
    </>
  );
}

const ICONS = {
  bar: (
    <svg className="ico" viewBox="0 0 100 40" fill="currentColor" aria-hidden="true">
      <rect x="0" y="8" width="8" height="24" rx="2" />
      <rect x="10" y="2" width="9" height="36" rx="2" />
      <rect x="19" y="17" width="62" height="6" />
      <rect x="81" y="2" width="9" height="36" rx="2" />
      <rect x="92" y="8" width="8" height="24" rx="2" />
    </svg>
  ),
  kb: (
    <svg className="ico" viewBox="0 0 60 70" fill="currentColor" aria-hidden="true">
      <path d="M18 4h24a8 8 0 0 1 8 8v8h-6v-7a3 3 0 0 0-3-3H19a3 3 0 0 0-3 3v7h-6v-8a8 8 0 0 1 8-8z" />
      <circle cx="30" cy="44" r="24" />
    </svg>
  ),
  rings: (
    <svg className="ico" viewBox="0 0 80 70" fill="none" stroke="currentColor" strokeWidth="6" aria-hidden="true">
      <path d="M22 0v30M58 0v30" />
      <circle cx="22" cy="48" r="16" />
      <circle cx="58" cy="48" r="16" />
    </svg>
  ),
  person: (
    <svg className="ico" viewBox="0 0 60 80" fill="currentColor" aria-hidden="true">
      <circle cx="30" cy="18" r="14" />
      <path d="M4 80c0-20 11-34 26-34s26 14 26 34z" />
    </svg>
  ),
};
export type PhotoIcon = keyof typeof ICONS;

const IMG = { eager: "eager", lazy: "lazy", high: "high" } as const;

/** An SVG drawing that covers its box (`preserveAspectRatio`). */
export const SVG_SLICE = ["xMidYMid", "slice"].join(" ");

/**
 * A photo, or the palette's gradient with a training icon when the box has
 * none. `parallax` moves it slower than the page (transform only).
 */
export function Photo({
  url,
  alt = "",
  icon = "bar",
  caption,
  className = "",
  parallax,
  priority = false,
  style,
}: {
  url?: string | null;
  alt?: string;
  icon?: PhotoIcon | null;
  caption?: string | null;
  className?: string;
  parallax?: number;
  priority?: boolean;
  style?: CSSProperties;
}) {
  return (
    <div className={`ph ${url ? "has-img" : ""} ${className}`} data-par={parallax} style={style}>
      {url ? (
        // eslint-disable-next-line @next/next/no-img-element -- media from the box's storage
        <img src={url} alt={alt} loading={priority ? IMG.eager : IMG.lazy} fetchPriority={priority ? IMG.high : undefined} decoding="async" />
      ) : icon ? (
        ICONS[icon]
      ) : null}
      {caption ? <span className="cap">{caption}</span> : null}
    </div>
  );
}

export function Stars({ value, label }: { value: number; label?: string }) {
  const full = Math.max(0, Math.min(5, Math.round(value)));
  return (
    <span className="stars" role="img" aria-label={label}>
      {"★★★★★".slice(0, full)}
      {"☆☆☆☆☆".slice(0, 5 - full)}
    </span>
  );
}

/** «75 €»: whole amounts without decimals, as on a price list. */
export function money(cents: number, currency: string, locale: string) {
  try {
    return new Intl.NumberFormat(locale, { style: "currency", currency: currency || "EUR", minimumFractionDigits: cents % 100 === 0 ? 0 : 2, maximumFractionDigits: 2 }).format(cents / 100);
  } catch {
    return `${(cents / 100).toFixed(2)} ${currency}`;
  }
}

export const BILLING_PERIODS = ["monthly", "quarterly", "semiannual", "annual"] as const;

/** «τον μήνα», «μία φορά»: what a package's price is for. */
export function usePeriodLabel() {
  const { t } = useSiteText();
  return (period: string | null | undefined, type?: string | null) =>
    (BILLING_PERIODS as readonly string[]).includes(period ?? "") ? t(`per.${period}`) : type === "trial" ? t("per.once") : "";
}

/** `<it>…</it>` in a message: the template's light italic accent (Ατελιέ). */
export function italic(chunks: ReactNode) {
  return <span className="it">{chunks}</span>;
}
