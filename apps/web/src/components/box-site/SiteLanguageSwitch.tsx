"use client";

import { useTranslations } from "next-intl";

import { siteLanguageCookie, type SiteLanguage } from "@/lib/public-site";

/**
 * ADR-388: the website's EL/EN switch. The choice is remembered, so the
 * browser's language no longer decides on the next visit.
 */
export function SiteLanguageSwitch({ slug, boxLanguage, language, basePath }: { slug: string; boxLanguage: string; language: SiteLanguage; basePath: string }) {
  const t = useTranslations("BoxSite");
  if (boxLanguage === "en") return null;
  const options: { value: SiteLanguage; code: string; href: string }[] = [
    { value: "box", code: boxLanguage, href: basePath || "/" },
    { value: "en", code: "en", href: `${basePath}/en` },
  ];
  function remember(value: SiteLanguage) {
    const code = value === "en" ? "en" : boxLanguage;
    document.cookie = siteLanguageCookie(slug, code, window.location.protocol === "https:");
  }
  return (
    <nav aria-label={t("languageLabel")} className="flex h-10 items-center gap-0.5 rounded-full p-1" style={{ background: "var(--media-control)" }} data-testid="site-language-switch">
      {options.map((option) => {
        const current = option.value === language;
        return (
          <a
            key={option.value}
            href={option.href}
            hrefLang={option.code}
            lang={option.code}
            aria-current={current ? "page" : undefined}
            onClick={() => remember(option.value)}
            className="grid h-8 min-w-9 place-items-center rounded-full px-2 text-xs font-extrabold uppercase"
            style={current ? { background: "var(--on-media)", color: "var(--media-control)" } : { color: "var(--on-media)" }}
          >
            {option.code}
          </a>
        );
      })}
    </nav>
  );
}

