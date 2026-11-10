"use client";

import { useTranslations } from "next-intl";

import { LanguageFlag } from "@/components/ui/LanguageFlag";
import { currentFirst, languageDir, languageShortCode, nativeLanguageName } from "@/lib/language-flags";
import { rememberSiteLanguage, siteLanguagePath, type SiteLanguage } from "@/lib/public-site";

import { useSite, useSiteText } from "../site-context";
import { OverlayShell } from "./overlays";

/** The address of this page in another of the site's languages. */
export function useLanguageHref() {
  const { site, rootBase, pageKey } = useSite();
  const valueOf = (code: string): SiteLanguage => (code === site.languages[0] ? "box" : code);
  return {
    valueOf,
    hrefFor: (code: string) => {
      const root = siteLanguagePath(rootBase, valueOf(code));
      return pageKey === "home" ? root : `${root === "/" ? "" : root}/${pageKey}`;
    },
  };
}

function useCurrentLanguage() {
  const { site, language } = useSite();
  return language === "box" ? site.languages[0] : language;
}

/**
 * ADR-545: «🇬🇷 EL ▾» at the top right of the website's bar and in its
 * footer; it opens the list of the languages the owner shows. Hidden with
 * one language.
 */
export function SiteLanguageButton({ testId = "site-language-button" }: { testId?: string } = {}) {
  const { site, open } = useSite();
  const { tb } = useSiteText();
  const tl = useTranslations("LanguageMenu");
  const current = useCurrentLanguage();
  if (site.languages.length < 2) return null;
  return (
    <button
      type="button"
      className="langBtn"
      aria-haspopup="dialog"
      aria-label={tl("button", { language: nativeLanguageName(current) })}
      title={tb("languageLabel")}
      onClick={() => open({ kind: "languages" })}
      data-testid={testId}
    >
      <LanguageFlag code={current} size={20} />
      <span>{languageShortCode(current)}</span>
      <span aria-hidden="true" className="caret">
        ▾
      </span>
    </button>
  );
}

/** The list: the current language first, then the others; each row a flag, its code and its own name. */
export function LanguagesSheet() {
  const { site, close, preview } = useSite();
  const { t, tb } = useSiteText();
  const tl = useTranslations("LanguageMenu");
  const current = useCurrentLanguage();
  const { valueOf, hrefFor } = useLanguageHref();
  const ordered = currentFirst(site.languages, current);
  const row = (code: string) => {
    const on = code === current;
    return (
      <li key={code}>
        <a
          href={hrefFor(code)}
          hrefLang={code}
          aria-current={on ? "page" : undefined}
          className="langRow"
          data-testid={`site-language-option-${code}`}
          onClick={(event) => {
            if (preview) {
              event.preventDefault();
              close();
              return;
            }
            rememberSiteLanguage(site.slug, valueOf(code) === "box" ? site.language : code);
          }}
        >
          <LanguageFlag code={code} size={24} />
          <span className="cd">{languageShortCode(code)}</span>
          <span className="nm" lang={code} dir={languageDir(code)}>
            {nativeLanguageName(code)}
          </span>
          <span aria-hidden="true" className="ck">
            {on ? "✓" : ""}
          </span>
        </a>
      </li>
    );
  };
  return (
    <OverlayShell label={tb("languageLabel")} testId="site-languages">
      <div className="scrim" aria-hidden="true" onClick={close} />
      <div className="sheet langSheet">
        <div className="grab" aria-hidden="true" />
        <button type="button" className="x" onClick={close} aria-label={t("close")} data-dialog-close>
          ✕
        </button>
        <h2>{tb("languageLabel")}</h2>
        <p className="langGroup">{tl("current")}</p>
        <ul>{row(ordered[0])}</ul>
        {ordered.length > 1 ? (
          <>
            <p className="langGroup">{tl("others")}</p>
            <ul>{ordered.slice(1).map(row)}</ul>
          </>
        ) : null}
      </div>
    </OverlayShell>
  );
}
