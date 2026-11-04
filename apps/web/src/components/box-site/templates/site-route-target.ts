import { siteLanguageFromSegment, type SiteLanguage } from "@/lib/public-site";

import { isSubPage, type SitePage } from "./site-model";

/**
 * ADR-530: what `/b/<slug>/<segment>[/<page>]` asks for. One segment is a
 * page in the box's language (`/schedule`) or a translation's home (`/en`);
 * two are a page in a translation (`/en/schedule`). Null is a 404.
 */
export function siteRouteTarget(segment: string, page?: string): { language: SiteLanguage; pageKey: SitePage } | null {
  if (page === undefined) {
    const key = segment.toLowerCase();
    if (isSubPage(key)) return { language: "box", pageKey: key };
    const language = siteLanguageFromSegment(segment);
    return language ? { language, pageKey: "home" } : null;
  }
  const language = siteLanguageFromSegment(segment);
  const key = page.toLowerCase();
  return language && isSubPage(key) ? { language, pageKey: key } : null;
}
