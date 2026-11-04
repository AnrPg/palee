"use client";

import "./site.css";

import { useQuery } from "@tanstack/react-query";
import { useLocale } from "next-intl";
import { useCallback, useEffect, useId, useMemo, useRef, useState, type CSSProperties, type ReactNode } from "react";

import type { PublicSiteV2 } from "@/api/box-site";
import { fetchPublicPackages, publicPackagesKey } from "@/api/my-payments";
import type { PublicBoxPage } from "@/api/social";
import { SiteConsentProvider } from "@/components/box-site/SiteConsent";
import { isAppLocale, localeDirection } from "@/i18n/locales";
import { FRESHNESS } from "@/lib/query-policy";
import { siteLanguageCode, siteLanguagePath, translatedPage, type SiteLanguage } from "@/lib/public-site";

import { ArenaTemplate } from "./ArenaTemplate";
import { AtelierTemplate } from "./AtelierTemplate";
import { useSiteMotion } from "./motion";
import { siteTokens, type SiteTokens, type TemplateKey } from "./palettes";
import { SiteProvider, settlePageTransition, usePageNavigation, type Overlay, type SiteCtx } from "./site-context";
import { galleryPhotos, normalizeSite, openingSpans, packageList, storyKinds, visibleSections } from "./site-data";
import { siteFontClass } from "./site-fonts";
import { siteCta, sitePages, type SitePage } from "./site-model";
import { StoriesTemplate } from "./StoriesTemplate";
import { TileDetail, TilesTemplate } from "./TilesTemplate";
import { FormSheet, Lightbox, MenuOverlay } from "./widgets/overlays";
import { StoryViewer } from "./widgets/stories";

export type BoxWebsiteProps = {
  page: PublicBoxPage;
  site: PublicSiteV2;
  language: SiteLanguage;
  /** `/b/<slug>`, `/b/<slug>/<code>` or "" on the box's own domain. */
  basePath: string;
  standalone: boolean;
  /** The page shown (its own URL, ADR-530 §4). */
  pageKey: SitePage;
  /**
   * The settings page's preview: links switch pages through this callback
   * instead of navigating, forms do not send, and the frame is a phone or a
   * desktop.
   */
  preview?: { device: "phone" | "desk"; onNavigate: (page: SitePage) => void };
};

const TEMPLATE_CLASS: Record<TemplateKey, string> = { arena: "tA", tiles: "tB", stories: "tC", atelier: "tD" };

const css = (tokens: SiteTokens) =>
  Object.entries(tokens)
    .map(([name, value]) => `${name}:${value}`)
    .join(";");

/**
 * ADR-530: the box's website in the owner's template, palette and mode.
 * The same component serves guests (server-rendered), the box's own domain
 * and the settings page's live preview (`preview`), where it draws its own
 * frame so the fixed bars and layers stay inside the phone or the desktop.
 */
export function BoxWebsite({ page: rawPage, site: rawSite, language, basePath, standalone, pageKey, preview }: BoxWebsiteProps) {
  const site = useMemo(() => normalizeSite(rawSite), [rawSite]);
  const page = useMemo(() => translatedPage(rawPage, site), [rawPage, site]);
  const slug = page.box.slug;
  const appLocale = useLocale();
  const id = `bw${useId().replace(/[^a-zA-Z0-9]/g, "")}`;

  // The base without the language, and the base of this language.
  const code = language === "box" ? null : language.toLowerCase();
  const rootBase = code && basePath.toLowerCase().endsWith(`/${code}`) ? basePath.slice(0, -code.length - 1) : basePath;
  const languageBase = siteLanguagePath(rootBase, language);
  const base = languageBase === "/" ? "" : languageBase;

  const packagesQuery = useQuery({
    queryKey: publicPackagesKey(slug),
    queryFn: () => fetchPublicPackages(slug),
    staleTime: FRESHNESS.reference,
    retry: false,
    enabled: site.sections.includes("packages"),
  });
  const packages = useMemo(() => packageList(packagesQuery.data), [packagesQuery.data]);
  const onlinePayments = Boolean((packagesQuery.data as { online_payments?: boolean } | undefined)?.online_payments);
  const gallery = useMemo(() => galleryPhotos(site, page), [site, page]);
  const visible = useMemo(() => visibleSections({ site, page, packages: packages.length, gallery: gallery.length }), [site, page, packages.length, gallery.length]);
  const pages = useMemo(() => sitePages(visible), [visible]);
  const spans = useMemo(() => openingSpans(page), [page]);
  const stories = useMemo(() => storyKinds(visible), [visible]);
  const cta = siteCta({ trial: visible.includes("trial_form"), contact: visible.includes("contact_form") }, site.phone);
  const contentLanguage = siteLanguageCode(language, site.language);
  // Dates and numbers follow the language the visitor reads the buttons in.
  const locale = appLocale || contentLanguage;
  const direction = isAppLocale(contentLanguage) ? localeDirection(contentLanguage) : "ltr";
  const calm = site.calm_motion;

  // What is open belongs to the page it was opened on: a page change closes it.
  const [opened, setOpened] = useState<{ overlay: Overlay; page: SitePage } | null>(null);
  const overlay = opened && opened.page === pageKey ? opened.overlay : null;
  const setOverlay = useCallback((next: Overlay) => setOpened({ overlay: next, page: pageKey }), [pageKey]);
  const close = useCallback(() => setOpened(null), []);
  const navigate = usePageNavigation(base, preview, calm);
  const rootRef = useRef<HTMLDivElement>(null);
  const siteRef = useRef<HTMLDivElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  // A new page ends its View Transition and starts at the top.
  useEffect(() => {
    settlePageTransition();
    if (preview) scrollRef.current?.scrollTo?.({ top: 0 });
  }, [pageKey, preview]);

  useSiteMotion({ root: rootRef, site: siteRef, scroller: preview ? scrollRef : null, calm, locale, key: `${site.template}-${pageKey}-${visible.join(",")}` });

  const ctx: SiteCtx = {
    page,
    site,
    template: site.template,
    packages,
    onlinePayments,
    visible,
    on: (section) => visible.includes(section as (typeof visible)[number]),
    pages,
    pageKey,
    base,
    rootBase,
    language,
    contentLanguage,
    locale,
    standalone,
    preview: Boolean(preview),
    calm,
    cta,
    gallery,
    spans,
    stories,
    siteRef,
    open: setOverlay,
    close,
    overlay,
    navigate,
    act: (choice = "", kind) => {
      const form = kind ?? (cta.kind === "trial" ? "trial" : cta.kind === "contact" ? "contact" : null);
      if (form === "trial" && !visible.includes("trial_form")) return;
      if (form === "contact" && !visible.includes("contact_form")) return;
      if (form) setOverlay({ kind: "form", form, choice });
    },
  };

  // Forced modes are inline; «Αυτόματο» follows the visitor's system in CSS, so the server's HTML is already right.
  const light = siteTokens(site.palette, false, site.template).tokens;
  const dark = siteTokens(site.palette, true, site.template).tokens;
  const forced = site.appearance === "auto" ? null : site.appearance === "dark" ? dark : light;

  const Template = { arena: ArenaTemplate, tiles: TilesTemplate, stories: StoriesTemplate, atelier: AtelierTemplate }[site.template] ?? ArenaTemplate;

  const body = (
    <div
      ref={rootRef}
      data-bw={id}
      data-testid="box-website"
      data-template={site.template}
      data-page={pageKey}
      className={`bw ${TEMPLATE_CLASS[site.template]} ${calm ? "calm" : ""} ${siteFontClass}`}
      lang={contentLanguage}
      dir={direction}
      style={forced ? ({ ...forced, colorScheme: site.appearance } as CSSProperties) : undefined}
    >
      {forced ? null : <style>{`[data-bw=${id}]{${css(light)}}@media (prefers-color-scheme: dark){[data-bw=${id}]{${css(dark)};color-scheme:dark}}`}</style>}
      <SiteProvider value={ctx}>
        <Template />
        <OverlayLayer overlay={overlay} />
      </SiteProvider>
    </div>
  );

  const framed: ReactNode = preview ? (
    <div className="bw-frame" data-device={preview.device} data-testid="box-website-preview">
      <div className="bw-scroll" ref={scrollRef}>
        {body}
      </div>
    </div>
  ) : (
    body
  );
  if (preview) return framed;
  return (
    <SiteConsentProvider slug={slug} site={site}>
      {framed}
    </SiteConsentProvider>
  );
}

function OverlayLayer({ overlay }: { overlay: Overlay | null }) {
  if (!overlay) return null;
  switch (overlay.kind) {
    case "form":
      return <FormSheet kind={overlay.form} choice={overlay.choice} />;
    case "menu":
      return <MenuOverlay />;
    case "light":
      return <Lightbox start={overlay.index} />;
    case "story":
      return <StoryViewer start={overlay.index} />;
    case "tile":
      return <TileDetail tile={overlay.tile} />;
  }
}
