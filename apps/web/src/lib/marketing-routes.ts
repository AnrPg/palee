/**
 * Στατιστικά & Μάρκετινγκ › Μάρκετινγκ (ANR 2026-11-04, option A): the home of
 * challenges, the box's promotions, partner perks (ADR-191) and referrals.
 * Packages stay in Οικονομικά; the Marketing tab only links to them.
 * Who may open each area did not change with the move.
 */
export const MARKETING_TAB_HREF = "/admin/metrics?tab=marketing";

export const MARKETING_ROUTES = {
  challenges: "/admin/marketing/challenges",
  promotions: "/admin/marketing/promotions",
  perks: "/admin/marketing/perks",
  referrals: "/admin/marketing/referrals",
} as const;

export type MarketingArea = keyof typeof MARKETING_ROUTES;

/** Any one of these opens the area (the API's route capabilities). */
export const MARKETING_CAPABILITIES: Record<MarketingArea, readonly string[]> = {
  challenges: ["manage_challenges"],
  promotions: ["manage_promotions", "view_promotions"],
  perks: ["manage_perks"],
  referrals: ["manage_promotions", "view_promotions"],
};

/** Finance tabs that moved: where `/admin/finance?tab=…` now lives. */
function movedFinanceTab(search: URLSearchParams): MarketingArea | null {
  const tab = search.get("tab");
  if (tab === "promotions") return search.get("offers") === "partners" ? "perks" : "promotions";
  if (tab === "referrals") return "referrals";
  return null;
}

function withQuery(path: string, search: URLSearchParams) {
  const query = search.toString();
  return query ? `${path}?${query}` : path;
}

/**
 * Where an old address of a moved page leads now (path relative to the
 * business, with its query), or null. Notifications, emails, guides and
 * bookmarks made before the move keep working: an open campaign
 * (`?campaign=`), a new form (`?new=`) or a referral sheet stay open.
 */
export function movedAdminTarget(relativePath: string, search: URLSearchParams): string | null {
  const path = relativePath.replace(/\/$/, "") || "/";
  if (path === "/admin/challenges") return withQuery(MARKETING_ROUTES.challenges, search);
  if (path === "/admin/metrics/marketing" || path === "/admin/marketing") return MARKETING_TAB_HREF;
  if (path === "/admin/finance") {
    const area = movedFinanceTab(search);
    if (!area) return null;
    const rest = new URLSearchParams(search);
    rest.delete("tab");
    rest.delete("offers");
    return withQuery(MARKETING_ROUTES[area], rest);
  }
  return null;
}

/** The redirect for a request URL (`/org/<slug>` kept), or null when the page did not move. */
export function movedAdminPageRedirect(url: URL): URL | null {
  const match = url.pathname.match(/^(\/org\/[^/]+)?(\/admin(?:\/.*)?)$/);
  if (!match) return null;
  const target = movedAdminTarget(match[2], url.searchParams);
  if (!target) return null;
  const next = new URL(`${match[1] ?? ""}${target}`, url);
  next.hash = url.hash;
  return next;
}
