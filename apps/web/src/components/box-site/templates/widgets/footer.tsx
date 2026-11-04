"use client";

import Link from "next/link";

import { isAppLocale, LOCALE_NAMES } from "@/i18n/locales";
import { rememberSiteLanguage, siteLanguagePath, type SiteLanguage } from "@/lib/public-site";

import { useSiteConsent } from "../../SiteConsent";
import { useSite, useSiteText } from "../site-context";

/**
 * The website's footer: the box and its phone, «Επικοινωνία», privacy,
 * «Cookies» (reopens the choice, ADR-354), «Φτιαγμένο με το Palee» and the
 * languages (ADR-388/520); the language links keep the page.
 */
export function SiteFooter() {
  const { page, site, on, act, rootBase, language, pageKey, preview } = useSite();
  const { t, tb } = useSiteText();
  const consent = useSiteConsent();
  const year = new Date().getFullYear();
  const privacyHref = `${rootBase}/privacy${language === "box" ? "" : `?lang=${encodeURIComponent(language)}`}`;
  const guard = preview ? (event: React.MouseEvent) => event.preventDefault() : undefined;
  const languages = site.languages.length > 1 ? site.languages : [];
  return (
    <footer className="foot" data-testid="site-footer">
      <div className="wrapx">
        <span>
          © {year} {page.box.name}
          {site.phone ? (
            <>
              {" · "}
              <a href={`tel:${site.phone.replace(/[^\d+]/g, "")}`} style={{ textDecoration: "none" }}>
                {site.phone}
              </a>
            </>
          ) : null}
        </span>
        <span className="links">
          {on("contact_form") ? (
            <button type="button" onClick={() => act("", "contact")}>
              {t("footer.contact")}
            </button>
          ) : null}
          <Link href={privacyHref} onClick={guard}>
            {tb("privacy")}
          </Link>
          {site.tracking.consent_required ? (
            <button type="button" onClick={consent.open}>
              {tb("cookies")}
            </button>
          ) : null}
          <span>{tb("poweredBy")}</span>
        </span>
        {languages.length ? (
          <nav className="langs" aria-label={tb("languageLabel")} data-testid="site-language-switch">
            {languages.map((code, index) => {
              const value: SiteLanguage = index === 0 ? "box" : code;
              const root = siteLanguagePath(rootBase, value);
              const href = pageKey === "home" ? root : `${root === "/" ? "" : root}/${pageKey}`;
              return (
                <a
                  key={code}
                  href={href}
                  hrefLang={code}
                  lang={code}
                  title={isAppLocale(code) ? LOCALE_NAMES[code] : code}
                  aria-current={value === language ? "page" : undefined}
                  onClick={(event) => {
                    if (preview) {
                      event.preventDefault();
                      return;
                    }
                    rememberSiteLanguage(site.slug, value === "box" ? site.language : code);
                  }}
                >
                  {code.split("-")[0]}
                </a>
              );
            })}
          </nav>
        ) : null}
      </div>
    </footer>
  );
}
