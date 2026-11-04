import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

type Show = operations["PaleeWeb.MyFeaturesController.show"];

/** ADR-470: every optional feature of a business with whether it is on. */
export type BusinessFeatureMap = Show["responses"][200]["content"]["application/json"]["features"];
export type BusinessFeature = keyof BusinessFeatureMap;

export const businessFeaturesKey = (slug: string, locationIds?: string | null) =>
  ["business-features", slug, locationIds ?? "all"] as const;

/** GET /api/org/{slug}/me/features: any member of the business may read it. */
export async function fetchBusinessFeatures(
  token: string,
  slug: string,
  locationIds?: string | null,
): Promise<BusinessFeatureMap> {
  const query = locationIds ? `?${new URLSearchParams({ location_ids: locationIds }).toString()}` : "";
  const data = await apiRequest<{ features?: BusinessFeatureMap }>(
    `/org/${encodeURIComponent(slug)}/me/features${query}`,
    { token },
  );
  return (data?.features ?? {}) as BusinessFeatureMap;
}
