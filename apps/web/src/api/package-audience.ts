// ADR-553: who sees the box's subscription packages, on its Palee page and
// its website alike: the box's choice, each package's own and the people the
// box always shows (`show`) or never shows (`hide`) its packages to.
import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

export type PackageAudienceSettings = components["schemas"]["PackageAudienceSettings"];
export type PackageAudienceException = components["schemas"]["PackageAudienceException"];
export type BoxAudience = PackageAudienceSettings["audience"];
export type PackageAudience = BoxAudience | null;
export type AudienceEffect = PackageAudienceException["effect"];

export const PACKAGE_AUDIENCE_KEY = ["admin", "finance", "package-audience"] as const;

export function fetchPackageAudience(token: string) {
  return apiRequest<PackageAudienceSettings>("/admin/package-audience", { token });
}

export function setBoxAudience(token: string, audience: BoxAudience) {
  return apiRequest<PackageAudienceSettings>("/admin/package-audience", { method: "PUT", token, body: { audience } });
}

/** A package's own choice; null follows the box. */
export function setPackageAudience(token: string, packageId: string, audience: PackageAudience) {
  return apiRequest<{ id: string; audience: PackageAudience }>(`/admin/package-audience/packages/${encodeURIComponent(packageId)}`, {
    method: "PUT",
    token,
    body: { audience },
  });
}

/** ADR-596: the package the box's page and website feature («Προτεινόμενο»); null for none. */
export function setFeaturedPackage(token: string, packageId: string | null) {
  return apiRequest<PackageAudienceSettings>("/admin/package-audience/featured", { method: "PUT", token, body: { package_id: packageId } });
}

/** Adds or changes one person's exception, on a package or (null) every package. */
export function putAudienceException(token: string, body: { user_id: string; effect: AudienceEffect; package_id: string | null }) {
  return apiRequest<PackageAudienceSettings>("/admin/package-audience/exceptions", { method: "POST", token, body });
}

export function deleteAudienceException(token: string, id: string) {
  return apiRequest<PackageAudienceSettings>(`/admin/package-audience/exceptions/${encodeURIComponent(id)}`, { method: "DELETE", token });
}
