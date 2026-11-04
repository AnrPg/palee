import { getTranslations } from "next-intl/server";

import type { PublicSiteV2, SiteSection } from "@/api/box-site";
import type { PublicPackages } from "@/api/my-payments";
import type { PublicBoxPage } from "@/api/social";
import { DEFAULT_LOCALE, isAppLocale } from "@/i18n/locales";
import { loadPublicBox } from "@/lib/public-box";
import { loadPublicPackages, loadPublicSite, translatedPage, type SiteLanguage } from "@/lib/public-site";
import { siteOrigin } from "@/lib/site-url";

import { languageRoot } from "./seo";
import { galleryPhotos, normalizeSite, packageList, visibleSections } from "./site-data";
import { sitePages, type SitePage } from "./site-model";

/**
 * ADR-530: the server's read of a box's website, shared by the pages, their
 * metadata, `llms.txt` and the sitemap. Packages are read only when the
 * owner shows them (they decide whether «Πακέτα» is a page).
 */
export type LoadedWebsite = {
  /** The box page with the site's translations in it. */
  page: PublicBoxPage;
  /** The box page as the API sent it (the app view translates on its own). */
  rawPage: PublicBoxPage;
  site: PublicSiteV2;
  packagesData: PublicPackages | null;
  visible: SiteSection[];
};

export async function loadWebsite(slug: string, language: SiteLanguage): Promise<LoadedWebsite | null> {
  const rawPage = await loadPublicBox(slug);
  if (!rawPage) return null;
  const raw = await loadPublicSite(rawPage.box.slug, language === "box" ? null : language);
  if (!raw) return null;
  const site = normalizeSite(raw as Partial<PublicSiteV2>);
  const page = translatedPage(rawPage, site);
  const packagesData = site.sections.includes("packages") ? await loadPublicPackages(rawPage.box.slug) : null;
  const visible = visibleSections({ site, page, packages: packageList(packagesData).length, gallery: galleryPhotos(site, page).length });
  return { page, rawPage, site, packagesData, visible };
}

/** The site's absolute root in the box's language: its canonical URL, else `/b/<slug>` on the app's origin. */
export async function siteRootUrl(site: PublicSiteV2, slug: string) {
  if (site.canonical_url) return site.canonical_url.replace(/\/$/, "");
  const origin = await siteOrigin();
  return new URL(`/b/${slug}`, origin).toString().replace(/\/$/, "");
}

/** The absolute root of one language of the site. */
export function siteLanguageRoot(root: string, site: PublicSiteV2, language: SiteLanguage) {
  return languageRoot(root, language === "box" || language === site.language ? null : language);
}

/** The pages' names in the page's language, for titles and breadcrumbs. */
export async function sitePageNames(contentLanguage: string, visible: SiteSection[]): Promise<Record<SitePage, string>> {
  const locale = isAppLocale(contentLanguage) ? contentLanguage : DEFAULT_LOCALE;
  const t = await getTranslations({ locale, namespace: "SiteTemplates" });
  const labels = Object.fromEntries(sitePages(visible).map((entry) => [entry.key, entry.label]));
  return {
    home: t("pages.home"),
    schedule: t(`pages.${labels.schedule ?? "schedule"}`),
    packages: t("pages.packages"),
    coaches: t("pages.coaches"),
    space: t("pages.space"),
  };
}
