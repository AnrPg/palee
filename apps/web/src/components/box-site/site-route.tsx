import type { Metadata } from "next";
import { cookies, headers } from "next/headers";
import { notFound, permanentRedirect, redirect } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { dehydrate, HydrationBoundary, QueryClient } from "@tanstack/react-query";
import type { ReactNode } from "react";

import { publicPackagesKey } from "@/api/my-payments";
import { PublicBoxView } from "@/components/box-page/PublicBoxView";
import { SiteAudience } from "@/components/box-site/SiteAudience";
import { BoxWebsite } from "@/components/box-site/templates/BoxWebsite";
import { pageUrl, siteJsonLd } from "@/components/box-site/templates/seo";
import { packageList } from "@/components/box-site/templates/site-data";
import { pageIsShown, type SitePage } from "@/components/box-site/templates/site-model";
import { loadWebsite, siteLanguageRoot, sitePageNames, siteRootUrl } from "@/components/box-site/templates/site-server";
import { JsonLd } from "@/components/seo/JsonLd";
import { ClientMessagesProvider } from "@/i18n/client-messages-provider";
import { isAppLocale, LOCALE_COOKIE } from "@/i18n/locales";
import { loadPublicBox, previewLine } from "@/lib/public-box";
import { preferredSiteLanguage, rememberedSiteLanguage, SITE_LANGUAGE_COOKIE, siteLanguageCode, siteLanguagePath, type SiteLanguage } from "@/lib/public-site";

/** The header the proxy sets when it serves a box's own domain (ADR-354). */
export const SITE_HOST_HEADER = "x-palee-site-host";

const pageSuffix = (pageKey: SitePage) => (pageKey === "home" ? "" : `/${pageKey}`);
const join = (root: string, pageKey: SitePage) => `${root === "/" ? "" : root}${pageSuffix(pageKey)}` || "/";

/**
 * The public box page and, when the owner switched it on, the box's website
 * (ADR-142, ADR-352, ADR-388, ADR-520, ADR-530). `/b/<slug>` speaks the
 * box's language and `/b/<slug>/<code>` each translation the owner shows;
 * each has the website's pages under it (`/schedule`, `/packages`,
 * `/coaches`, `/space`). On the box's own domain the website stands alone.
 */
export async function siteMetadata(slug: string, language: SiteLanguage, pageKey: SitePage = "home"): Promise<Metadata> {
  const box = await loadPublicBox(slug);
  if (!box) return {};
  const tags = await getTranslations("BoxTags");
  const line = previewLine(box, (key) => tags(`discipline.${key}`));
  const loaded = await loadWebsite(box.box.slug, language);
  if (!loaded) {
    const description = box.profile.about?.slice(0, 200) || line;
    return {
      title: box.box.name,
      description,
      alternates: { canonical: `/b/${box.box.slug}` },
      openGraph: { title: box.box.name, description: line || description, type: "website", url: `/b/${box.box.slug}` },
      twitter: { card: "summary_large_image", title: box.box.name, description: line || description },
    };
  }
  const { site, page, visible } = loaded;
  const shown: SitePage = pageKey !== "home" && pageIsShown(pageKey, visible) ? pageKey : "home";
  const contentLanguage = siteLanguageCode(site.translation ?? "box", site.language);
  const names = await sitePageNames(contentLanguage, visible);
  const about = (site.translation && site.about?.trim() ? site.about : page.profile.about)?.replace(/\s+/g, " ").trim();
  const base = about?.slice(0, 200) || line;
  const title = shown === "home" ? page.box.name : `${names[shown]} · ${page.box.name}`;
  const description = shown === "home" ? base : `${title}. ${base}`.slice(0, 200);
  const root = await siteRootUrl(site, box.box.slug);
  const url = pageUrl(siteLanguageRoot(root, site, site.translation ?? "box"), shown);
  const languages =
    site.languages.length > 1
      ? Object.fromEntries([
          ...site.languages.map((code, index) => [code, pageUrl(siteLanguageRoot(root, site, index === 0 ? "box" : code), shown)]),
          ["x-default", pageUrl(root, shown)],
        ])
      : undefined;
  return {
    title,
    description,
    alternates: { canonical: url, ...(languages ? { languages } : {}) },
    // The image is the segment's opengraph-image: the box's cover, else its card.
    openGraph: { title, description: line || description, type: "website", url, locale: contentLanguage },
    twitter: { card: "summary_large_image", title, description: line || description },
  };
}

export async function SiteRoute({
  slug,
  language,
  pageKey = "home",
  appView,
}: {
  slug: string;
  language: SiteLanguage;
  pageKey?: SitePage;
  /** The app's own view of this address for signed-in members (the box page unless given). */
  appView?: ReactNode;
}) {
  const loaded = await loadPublicBox(slug);
  if (!loaded) notFound();
  const languageSuffix = language === "box" ? "" : `/${language.toLowerCase()}`;
  if (loaded.box.slug !== slug) permanentRedirect(`/b/${loaded.box.slug}${languageSuffix}${pageSuffix(pageKey)}`);
  const requestHeaders = await headers();
  const standalone = Boolean(requestHeaders.get(SITE_HOST_HEADER));
  const base = standalone ? "" : `/b/${loaded.box.slug}`;
  const home = base || "/";
  const website = await loadWebsite(loaded.box.slug, language);
  if (!website) {
    if (appView) return <>{appView}</>;
    if (language !== "box" || pageKey !== "home") redirect(home);
    return <PublicBoxView page={loaded} />;
  }
  const { site, page, visible, packagesData } = website;
  // A translation the owner hides (or the box's own language under its code) is the box's page.
  if (language !== "box" && !site.translation) redirect(join(home, pageKey));

  const jar = await cookies();
  const appLocaleChosen = isAppLocale(jar.get(LOCALE_COOKIE)?.value);
  const choice = rememberedSiteLanguage(jar.get(SITE_LANGUAGE_COOKIE)?.value, loaded.box.slug);

  if (language === "box") {
    const preferred = preferredSiteLanguage({
      boxLanguage: site.language,
      languages: site.languages,
      acceptLanguage: requestHeaders.get("accept-language"),
      siteChoice: choice,
      appLocaleChosen,
    });
    if (preferred) redirect(join(siteLanguagePath(base, preferred), pageKey));
  }

  const siteLanguage: SiteLanguage = site.translation ?? language;
  // A page the owner leaves without sections is not in the menu: its address goes home.
  if (pageKey !== "home" && !pageIsShown(pageKey, visible)) {
    if (appView) return <>{appView}</>;
    redirect(siteLanguagePath(base, siteLanguage));
  }

  const contentLanguage = siteLanguageCode(siteLanguage, site.language);
  const names = await sitePageNames(contentLanguage, visible);
  const root = await siteRootUrl(site, loaded.box.slug);
  const jsonLd = siteJsonLd({ page, site, packages: packageList(packagesData), visible, pageKey, root: siteLanguageRoot(root, site, siteLanguage), names });

  const queries = new QueryClient();
  if (packagesData) queries.setQueryData(publicPackagesKey(loaded.box.slug), packagesData);
  const websiteView = (
    <HydrationBoundary state={dehydrate(queries)}>
      <JsonLd data={jsonLd} />
      <BoxWebsite page={loaded} site={site} language={siteLanguage} basePath={base} standalone={standalone} pageKey={pageKey} />
    </HydrationBoundary>
  );
  const view = standalone ? (
    websiteView
  ) : (
    <SiteAudience website={websiteView} app={appView ?? <PublicBoxView page={page} site={site} standalone={false} language={siteLanguage} />} />
  );
  // People who chose the app's language keep it on the box-language page; a translation is that language for all.
  const locale = language !== "box" ? site.translation : appLocaleChosen ? null : site.language;
  if (!locale || !isAppLocale(locale)) return view;
  return (
    <div lang={locale} className="contents">
      <ClientMessagesProvider locale={locale} timeZone={site.time_zone}>
        {view}
      </ClientMessagesProvider>
    </div>
  );
}
