"use client";

import Link from "next/link";

import { useSiteConsent } from "../../SiteConsent";
import { useSite, useSiteText } from "../site-context";
import { SiteLanguageButton } from "./languages";

/**
 * The website's footer: the box and its phone, «Επικοινωνία», privacy,
 * «Cookies» (reopens the choice, ADR-354), «Φτιαγμένο με το Palee» and the
 * same language button as the bar (ADR-545: «🇬🇷 EL ▾» opening the list of
 * the languages the owner shows), never a row of bare codes.
 */
export function SiteFooter() {
  const { page, site, on, act, rootBase, language, preview } = useSite();
  const { t, tb } = useSiteText();
  const consent = useSiteConsent();
  const year = new Date().getFullYear();
  const privacyHref = `${rootBase}/privacy${language === "box" ? "" : `?lang=${encodeURIComponent(language)}`}`;
  const guard = preview ? (event: React.MouseEvent) => event.preventDefault() : undefined;
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
          {site.report_contact ? (
            // ADR-397: where anyone reports content on the site (DSA Art. 16).
            <a href={`mailto:${site.report_contact}`} data-testid="site-report-contact">
              {tb("reportContact", { email: site.report_contact })}
            </a>
          ) : null}
          <span>{tb("poweredBy")}</span>
        </span>
        <SiteLanguageButton testId="site-footer-language-button" />
      </div>
    </footer>
  );
}
