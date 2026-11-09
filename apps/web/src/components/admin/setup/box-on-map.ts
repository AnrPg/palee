import type { FacilityLocation } from "@/api/facility";

/**
 * Whether Γύρω μου can place the box (ADR-583 Ε4): some live location has a
 * map pin or at least a town, which the same-town fallback matches.
 */
export function boxFindableByPlace(locations: readonly Pick<FacilityLocation, "archived_at" | "city" | "latitude" | "longitude">[]): boolean {
  return locations.some(
    (location) =>
      !location.archived_at &&
      ((typeof location.latitude === "number" && typeof location.longitude === "number") || Boolean(location.city?.trim())),
  );
}
