"use client";

import { LanguageMenu } from "@/components/ui/LanguageMenu";
import { rememberSiteLanguage, siteLanguagePath, type SiteLanguage } from "@/lib/public-site";

/**
 * ADR-388/500/545: the website's language button on the box's page header:
 * the box's own language and each translation the owner shows, as
 * «🇬🇷 EL ▾» that opens the list. Each language is its own address; the
 * choice is remembered, so the browser's language no longer decides on the
 * next visit.
 */
export function SiteLanguageSwitch({
  slug,
  boxLanguage,
  languages,
  language,
  basePath,
}: {
  slug: string;
  boxLanguage: string;
  languages: string[];
  language: SiteLanguage;
  basePath: string;
}) {
  if (languages.length < 2) return null;
  const valueOf = (code: string): SiteLanguage => (code === languages[0] ? "box" : code);
  const current = language === "box" ? languages[0] : language;
  return (
    <LanguageMenu
      value={current}
      options={languages}
      tone="media"
      hrefFor={(code) => siteLanguagePath(basePath, valueOf(code))}
      onChoose={(code) => rememberSiteLanguage(slug, valueOf(code) === "box" ? boxLanguage : code)}
      testId="site-language-menu"
    />
  );
}
