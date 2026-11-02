import type { Metadata } from "next";
import { cookies, headers } from "next/headers";
import { notFound, permanentRedirect, redirect } from "next/navigation";
import { getTranslations } from "next-intl/server";

import { PublicBoxView } from "@/components/box-page/PublicBoxView";
import { ClientMessagesProvider } from "@/i18n/client-messages-provider";
import { isAppLocale, LOCALE_COOKIE } from "@/i18n/locales";
import { loadPublicBox, previewLine } from "@/lib/public-box";
import { loadPublicSite, rememberedSiteLanguage, shouldOpenEnglish, siteText, SITE_LANGUAGE_COOKIE, type SiteLanguage } from "@/lib/public-site";

/** The header the proxy sets when it serves a box's own domain (ADR-354). */
export const SITE_HOST_HEADER = "x-palee-site-host";

/**
 * The public box page and, when the owner switched it on, the box's website
 * (ADR-142, ADR-352, ADR-388). `/b/<slug>` speaks the box's language and
 * `/b/<slug>/en` English; on the box's own domain the website stands alone.
 */
export async function siteMetadata(slug: string, language: SiteLanguage): Promise<Metadata> {
  const page = await loadPublicBox(slug);
  if (!page) return {};
  const site = await loadPublicSite(page.box.slug);
  const tags = await getTranslations("BoxTags");
  const line = previewLine(page, (key) => tags(`discipline.${key}`));
  const about = site ? siteText(language, page.profile.about, site.about_en) : page.profile.about;
  const description = about?.slice(0, 200) || line;
  const base = `/b/${page.box.slug}`;
  const path = language === "en" ? `${base}/en` : base;
  return {
    title: page.box.name,
    description,
    alternates: {
      canonical: path,
      ...(site && site.language !== "en" ? { languages: { [site.language]: base, en: `${base}/en`, "x-default": base } } : {}),
    },
    openGraph: { title: page.box.name, description: line || description, type: "website", url: path },
    twitter: { card: "summary_large_image", title: page.box.name, description: line || description },
  };
}

export async function SiteRoute({ slug, language }: { slug: string; language: SiteLanguage }) {
  const page = await loadPublicBox(slug);
  if (!page) notFound();
  const suffix = language === "en" ? "/en" : "";
  if (page.box.slug !== slug) permanentRedirect(`/b/${page.box.slug}${suffix}`);
  const site = await loadPublicSite(page.box.slug);
  if (!site) {
    if (language === "en") redirect(`/b/${page.box.slug}`);
    return <PublicBoxView page={page} />;
  }
  if (language === "en" && site.language === "en") redirect(`/b/${page.box.slug}`);

  const jar = await cookies();
  const requestHeaders = await headers();
  const standalone = Boolean(requestHeaders.get(SITE_HOST_HEADER));
  const appLocaleChosen = isAppLocale(jar.get(LOCALE_COOKIE)?.value);
  const choice = rememberedSiteLanguage(jar.get(SITE_LANGUAGE_COOKIE)?.value, page.box.slug);

  if (
    language === "box" &&
    shouldOpenEnglish({ boxLanguage: site.language, acceptLanguage: requestHeaders.get("accept-language"), siteChoice: choice, appLocaleChosen })
  ) {
    redirect(standalone ? "/en" : `/b/${page.box.slug}/en`);
  }

  const view = <PublicBoxView page={page} site={site} standalone={standalone} language={language} />;
  // People who chose the app's language keep it on the box-language page; English is English for all.
  const locale = language === "en" ? "en" : appLocaleChosen ? null : site.language;
  if (!locale || !isAppLocale(locale)) return view;
  return (
    <div lang={locale} className="contents">
      <ClientMessagesProvider locale={locale} timeZone={site.time_zone}>
        {view}
      </ClientMessagesProvider>
    </div>
  );
}
