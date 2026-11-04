"use client";

import type { PublicSiteV2 } from "@/api/box-site";
import type { PublicBoxPage } from "@/api/social";
import type { SiteLanguage } from "@/lib/public-site";

import type { SitePage } from "./site-model";

export type BoxWebsiteProps = {
  page: PublicBoxPage;
  site: PublicSiteV2;
  language: SiteLanguage;
  /** `/b/<slug>`, `/b/<slug>/<code>` or "" on the box's own domain. */
  basePath: string;
  standalone: boolean;
  /** The page shown (its own URL, ADR-530 §4). */
  pageKey: SitePage;
  /**
   * The settings page's preview: links switch pages through this callback
   * instead of navigating, forms do not send, and the frame is a phone or a
   * desktop.
   */
  preview?: { device: "phone" | "desk"; onNavigate: (page: SitePage) => void };
};

/** ADR-530: the box's website in the owner's template, palette and mode. Placeholder until the templates land. */
export function BoxWebsite(props: BoxWebsiteProps) {
  return <div data-testid="box-website" data-template={props.site.template} />;
}
