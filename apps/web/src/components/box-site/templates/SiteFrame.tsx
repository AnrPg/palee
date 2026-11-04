"use client";

import type { ReactNode } from "react";

import { useSite, useSiteText } from "./site-context";
import { SiteFooter } from "./widgets/footer";

/**
 * The page of every template: `.site` (header, main, footer) and the fixed
 * bars beside it. While a layer is open, both are inert.
 */
export function SiteFrame({ header, children, bars, mainClassName }: { header: ReactNode; children: ReactNode; bars?: ReactNode; mainClassName?: string }) {
  const { siteRef, overlay } = useSite();
  const { t } = useSiteText();
  const covered = overlay !== null;
  return (
    <>
      <div className="site" ref={siteRef} inert={covered}>
        <a className="skip" href="#bw-main">
          {t("skip")}
        </a>
        {header}
        <main id="bw-main" className={mainClassName} tabIndex={-1}>
          {children}
        </main>
        <SiteFooter />
      </div>
      {bars ? (
        <div className="bw-layer bars" inert={covered}>
          {bars}
        </div>
      ) : null}
    </>
  );
}
