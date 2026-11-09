import type { AroundKindResponse } from "@/api/around";

export type AroundReach = AroundKindResponse["reach"];

/**
 * The «Κοντά μου» card's title (ADR-583, ANR pick Ε1 B): «Κοντά μου» while
 * the list is within the person's radius; «Έως 25 km» when nothing was near
 * and the search widened; the town when it fell back to the same town.
 */
export function nearbyEyebrow(
  reach: AroundReach | null | undefined,
): { key: "nearMe" } | { key: "nearUpTo"; km: number } | { key: "nearInTown"; town: string } {
  if (!reach?.widened) return { key: "nearMe" };
  if (reach.scope === "town" && reach.town) return { key: "nearInTown", town: reach.town };
  if (reach.scope === "radius" && typeof reach.radius_km === "number") return { key: "nearUpTo", km: reach.radius_km };
  return { key: "nearMe" };
}
