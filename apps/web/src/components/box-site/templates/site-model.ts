import type { SiteSection } from "@/api/box-site";

/**
 * ADR-530: the page model every template shares. Sections are switches, not an
 * order; each template has its own flow. A page with nothing on it leaves the
 * menu, and the main button falls back from the trial form to the contact
 * form to a phone call.
 */

export const SITE_PAGES = ["home", "schedule", "packages", "coaches", "space"] as const;
export type SitePage = (typeof SITE_PAGES)[number];
/** Pages with their own URL (`/b/<slug>/<page>`); «home» is the site's root. */
export const SUB_PAGES = SITE_PAGES.filter((page) => page !== "home") as Exclude<SitePage, "home">[];

export function isSubPage(value: unknown): value is Exclude<SitePage, "home"> {
  return typeof value === "string" && (SUB_PAGES as readonly string[]).includes(value);
}

/** The settings page's groups, in the order the owner reads them. `fresh` marks a new section («νέο»). */
export const SECTION_GROUPS: { key: "basics" | "training" | "shop" | "team" | "forms"; sections: SiteSection[] }[] = [
  { key: "basics", sections: ["about", "photos", "stats"] as SiteSection[] },
  { key: "training", sections: ["schedule", "wod", "events", "programmes"] as SiteSection[] },
  { key: "shop", sections: ["packages"] },
  { key: "team", sections: ["coaches", "location", "reviews", "faq"] },
  { key: "forms", sections: ["trial_form", "contact_form"] },
];
export const NEW_SECTIONS = ["photos", "stats", "programmes"] as unknown as SiteSection[];
/** «Μόνο τα βασικά». */
export const BASIC_SECTIONS = ["about", "packages", "location", "trial_form"] as SiteSection[];

export type SitePageEntry = { key: SitePage; label: "home" | "schedule" | "training" | "packages" | "coaches" | "space" };

/** The menu: pages that have at least one visible section. `visible` is the site's `sections`. */
export function sitePages(visible: readonly SiteSection[]): SitePageEntry[] {
  const on = (key: string) => visible.includes(key as SiteSection);
  const pages: SitePageEntry[] = [{ key: "home", label: "home" }];
  if (on("schedule") || on("programmes") || on("events")) pages.push({ key: "schedule", label: on("schedule") ? "schedule" : "training" });
  if (on("packages")) pages.push({ key: "packages", label: "packages" });
  if (on("coaches")) pages.push({ key: "coaches", label: "coaches" });
  if (on("photos") || on("location") || on("reviews") || on("faq")) pages.push({ key: "space", label: "space" });
  return pages;
}

export type SiteCta = { kind: "trial" | "contact" | "call" | "none"; phone: string | null };

/** The one main button: trial form, else contact form, else the box's phone, else nothing. */
export function siteCta(forms: { trial: boolean; contact: boolean }, phone: string | null | undefined): SiteCta {
  if (forms.trial) return { kind: "trial", phone: phone ?? null };
  if (forms.contact) return { kind: "contact", phone: phone ?? null };
  if (phone) return { kind: "call", phone };
  return { kind: "none", phone: null };
}

/** The path of a page under the site's base (`/b/<slug>`, `/b/<slug>/en` or "" on the box's own domain). */
export function sitePagePath(base: string, page: SitePage) {
  if (page === "home") return base || "/";
  return `${base}/${page}`;
}
