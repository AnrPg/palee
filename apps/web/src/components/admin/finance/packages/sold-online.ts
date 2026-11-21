import type { FinanceRecord } from "@/api/finance";

/*
 * «Πωλείται online» (ADR-248/271, pilot mockup p1 option A). The API decides
 * whether box members see a package online and, if not, why
 * (`online_visibility`, from `PackageSale` on the server); this module only
 * turns that answer into copy keys, the list badge and the fix link. No rule
 * is repeated here.
 */

export const ONLINE_VISIBILITIES = ["visible", "free", "free_listed", "off", "purpose_off", "no_provider", "inactive"] as const;
export type OnlineVisibility = (typeof ONLINE_VISIBILITIES)[number];

export function onlineVisibility(pkg: FinanceRecord | null | undefined): OnlineVisibility {
  const value = pkg?.online_visibility;
  return ONLINE_VISIBILITIES.includes(value as OnlineVisibility) ? (value as OnlineVisibility) : "off";
}

/**
 * Whether box members see the package (the switch's state). ADR-291: with no
 * online payments, a paid package whose owner never chose is listed too, to
 * ask for («Το θέλω») and pay at the front desk.
 */
export function isSoldOnline(pkg: FinanceRecord | null | undefined): boolean {
  const visibility = onlineVisibility(pkg);
  if (visibility === "free") return false;
  return pkg?.sold_online === true || visibility === "no_provider" || visibility === "free_listed";
}

/** The switch cannot be turned on for a retired package. */
export function canSellOnline(visibility: OnlineVisibility): boolean {
  return visibility !== "inactive";
}

/**
 * ADR-681: a free package is shown, never sold: the switch reads
 * «Φαίνεται στη Σελίδα πακέτων» and the box activates it without payment.
 */
export function isFreeVisibility(visibility: OnlineVisibility): boolean {
  return visibility === "free" || visibility === "free_listed";
}

/** Marked «Πωλείται online» but members do not see it yet: shown in the warning colour. */
export function isHidden(visibility: OnlineVisibility): boolean {
  return visibility === "purpose_off";
}

/** The list badge: «Online», «Στην υποδοχή» (ADR-291), «Δωρεάν · στη σελίδα» (ADR-681), «Online · δεν φαίνεται», or none. */
export function badgeKey(visibility: OnlineVisibility): "badge" | "badgeDesk" | "badgeFree" | "badgeHidden" | null {
  if (visibility === "visible") return "badge";
  if (visibility === "no_provider") return "badgeDesk";
  if (visibility === "free_listed") return "badgeFree";
  if (isHidden(visibility)) return "badgeHidden";
  return null;
}

/** Where the owner fixes a package marked sold online that members cannot see. */
export function fixLink(visibility: OnlineVisibility): { href: string; labelKey: string } | null {
  if (visibility === "purpose_off") return { href: "/admin/settings?tab=payments", labelKey: "fix_purpose_off" };
  if (visibility === "no_provider") return { href: "/admin/settings?tab=payments", labelKey: "fix_no_provider" };
  return null;
}

export const PACKAGES_TAB_HREF = "/admin/finance?tab=packages";

/** The box's public Σελίδα πακέτων. */
export function salesPageHref(slug: string | null): string | null {
  return slug ? `/b/${encodeURIComponent(slug)}/packages` : null;
}

/** «Πωλούνται online: N από M»: of the packages that can be sold online (per the API), how many are. */
export function soldOnlineCount(packages: FinanceRecord[]): { count: number; total: number } {
  // ADR-681: free packages are shown, not sold, so they are not counted.
  const sellable = packages.filter((pkg) => {
    const visibility = onlineVisibility(pkg);
    return canSellOnline(visibility) && !isFreeVisibility(visibility);
  });
  return { count: sellable.filter(isSoldOnline).length, total: sellable.length };
}
