import type { Metadata } from "next";
import { cookies, headers } from "next/headers";
import { notFound, permanentRedirect, redirect } from "next/navigation";
import { getTranslations } from "next-intl/server";

import { PublicBoxView } from "@/components/box-page/PublicBoxView";
import { ClientMessagesProvider } from "@/i18n/client-messages-provider";
import { isAppLocale, LOCALE_COOKIE } from "@/i18n/locales";
import { loadPublicBox, previewLine } from "@/lib/public-box";
import {
  loadPublicSite,
  preferredSiteLanguage,
  rememberedSiteLanguage,
  SITE_LANGUAGE_COOKIE,
  siteLanguagePath,
  translatedPage,
  type SiteLanguage,
} from "@/lib/public-site";

/** The header the proxy sets when it serves a box's own domain (ADR-354). */
export const SITE_HOST_HEADER = "x-palee-site-host";

/**
 * The public box page and, when the owner switched it on, the box's website
 * (ADR-142, ADR-352, ADR-388, ADR-500). `/b/<slug>` speaks the box's
 * language and `/b/<slug>/<code>` each translation the owner shows; on the
 * box's own domain the website stands alone.
 */
export async function siteMetadata(slug: string, language: SiteLanguage): Promise<Metadata> {
  const page = await loadPublicBox(slug);
  if (!page) return {};
  const site = await loadPublicSite(page.box.slug, language === "box" ? null : language);
  const tags = await getTranslations("BoxTags");
  const line = previewLine(page, (key) => tags(`discipline.${key}`));
  const about = site?.translation && site.about?.trim() ? site.about : page.profile.about;
  const description = about?.slice(0, 200) || line;
  const base = `/b/${page.box.slug}`;
  const path = siteLanguagePath(base, site?.translation ?? "box");
  const languages =
    site && site.languages.length > 1
      ? Object.fromEntries([...site.languages.map((code, index) => [code, siteLanguagePath(base, index === 0 ? "box" : code)]), ["x-default", base]])
      : undefined;
  return {
    title: page.box.name,
    description,
    alternates: { canonical: path, ...(languages ? { languages } : {}) },
    openGraph: { title: page.box.name, description: line || description, type: "website", url: path },
    twitter: { card: "summary_large_image", title: page.box.name, description: line || description },
  };
}

export async function SiteRoute({ slug, language }: { slug: string; language: SiteLanguage }) {
  const loaded = await loadPublicBox(slug);
  if (!loaded) notFound();
  const suffix = language === "box" ? "" : `/${language.toLowerCase()}`;
  if (loaded.box.slug !== slug) permanentRedirect(`/b/${loaded.box.slug}${suffix}`);
  const requestHeaders = await headers();
  const standalone = Boolean(requestHeaders.get(SITE_HOST_HEADER));
  const base = standalone ? "" : `/b/${loaded.box.slug}`;
  const home = base || "/";
  const site = await loadPublicSite(loaded.box.slug, language === "box" ? null : language);
  if (!site) {
    if (language !== "box") redirect(home);
    return <PublicBoxView page={loaded} />;
  }
  // A translation the owner hides (or the box's own language under its code) is the box's page.
  if (language !== "box" && !site.translation) redirect(home);

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
    if (preferred) redirect(siteLanguagePath(base, preferred));
  }

  const page = translatedPage(loaded, site);
  const view = <PublicBoxView page={page} site={site} standalone={standalone} language={site.translation ?? language} />;
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
