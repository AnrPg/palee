"use client";

import { useTranslations } from "next-intl";

import { LOCALE_NAMES, isAppLocale } from "@/i18n/locales";
import { rememberSiteLanguage, siteLanguagePath, type SiteLanguage } from "@/lib/public-site";

/**
 * ADR-388/500: the website's language switch: the box's own language and
 * each translation the owner shows. The choice is remembered, so the
 * browser's language no longer decides on the next visit.
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
  const t = useTranslations("BoxSite");
  if (languages.length < 2) return null;
  const options = languages.map((code, index) => {
    const value: SiteLanguage = index === 0 ? "box" : code;
    return { value, code, href: siteLanguagePath(basePath, value) };
  });
  return (
    <nav aria-label={t("languageLabel")} className="flex h-10 max-w-full items-center gap-0.5 overflow-x-auto rounded-full p-1" style={{ background: "var(--media-control)" }} data-testid="site-language-switch">
      {options.map((option) => {
        const current = option.value === language;
        return (
          <a
            key={option.code}
            href={option.href}
            hrefLang={option.code}
            lang={option.code}
            title={isAppLocale(option.code) ? LOCALE_NAMES[option.code] : option.code}
            aria-current={current ? "page" : undefined}
            onClick={() => rememberSiteLanguage(slug, option.value === "box" ? boxLanguage : option.code)}
            className="grid h-8 min-w-9 shrink-0 place-items-center rounded-full px-2 text-xs font-extrabold uppercase"
            style={current ? { background: "var(--on-media)", color: "var(--media-control)" } : { color: "var(--on-media)" }}
          >
            {option.code.split("-")[0]}
          </a>
        );
      })}
    </nav>
  );
}
