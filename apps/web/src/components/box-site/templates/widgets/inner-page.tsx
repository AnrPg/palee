"use client";

import type { ReactNode } from "react";

import { Lines, useSite, useSiteText } from "../site-context";
import { Gallery, MapCard } from "./place";
import { BuyOnline, PackageCardsA, PackageMenu, PackageStack, PackageTiles } from "./packages";
import { Schedule } from "./schedule";
import { CoachGrid, Events, Faq, Programmes, Reviews } from "./social";

/**
 * The sub-pages (Πρόγραμμα, Πακέτα, Coaches, Ο χώρος), the same content in
 * every template with the template's own heading and spacing. Each block
 * shows only when its section is on and has data.
 */
export function InnerPage() {
  const { template, pageKey, on, page } = useSite();
  const { t } = useSiteText();

  const head = (title: string, sub?: string) => {
    switch (template) {
      case "arena":
        return (
          <section className="wrapx pagehead">
            <h1 className="big2 ld-go">
              <Lines lines={[title]} />
            </h1>
            {sub ? <p className="sub">{sub}</p> : null}
          </section>
        );
      case "atelier":
        return (
          <header className="pagehead">
            <span className="lab">{page.box.name}</span>
            <h1 className="h2D ld-go" style={{ margin: "12px 0 10px" }}>
              <Lines lines={[title]} />
            </h1>
            {sub ? <p className="sub">{sub}</p> : null}
          </header>
        );
      default:
        return (
          <header className="pagehead">
            <h1 className="ld-go">
              <Lines lines={[title]} />
            </h1>
            {sub ? <p className="sub">{sub}</p> : null}
          </header>
        );
    }
  };
  const block = (children: ReactNode, title?: string, testId?: string) => (
    <section className={template === "arena" ? "wrapx block" : "block"} data-testid={testId}>
      {title ? <h2 className="h2s">{title}</h2> : null}
      {children}
    </section>
  );

  switch (pageKey) {
    case "schedule":
      return (
        <>
          {head(on("schedule") ? t("schedule.title") : t("pages.training"), on("schedule") ? t("schedule.sub") : undefined)}
          {on("schedule") ? block(<Schedule />) : null}
          {on("events") ? block(<Events />, t("sections.events")) : null}
          {on("programmes") ? block(<Programmes />, t("sections.programmes")) : null}
        </>
      );
    case "packages": {
      const list = template === "arena" ? <PackageCardsA /> : template === "atelier" ? <PackageMenu /> : template === "stories" ? <PackageStack /> : <PackageTiles />;
      return (
        <>
          {head(t("packages.title"), template === "stories" ? t("packages.stackSub") : t("packages.sub"))}
          {block(
            <>
              {list}
              <BuyOnline />
            </>,
          )}
          {on("faq") ? block(<Faq />, t("sections.faq")) : null}
        </>
      );
    }
    case "coaches":
      return (
        <>
          {head(t("pages.coaches"), t("coaches.sub"))}
          {block(<CoachGrid />)}
        </>
      );
    case "space":
      return (
        <>
          {head(t("pages.space"), on("photos") ? t("space.sub") : undefined)}
          {on("photos") ? block(<Gallery />) : null}
          {on("location") ? block(<MapCard />, t("map.howToGet")) : null}
          {on("reviews") ? block(<Reviews />, t("sections.reviews")) : null}
          {on("faq") ? block(<Faq />, t("sections.faq")) : null}
        </>
      );
    default:
      return null;
  }
}
