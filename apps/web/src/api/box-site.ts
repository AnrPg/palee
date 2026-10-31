import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * The box's website (ADR-352..354) and Google review asks (ADR-355). No
 * screens use these yet: they wait for ANR's pick of the mockups
 * (v31-mockups/w4-web.html).
 */
export type PublicSite = components["schemas"]["PublicSiteResponse"];
export type SiteSettings = components["schemas"]["SiteSettings"];
export type SiteSettingsUpdate = components["schemas"]["SiteSettingsUpdate"];
export type SiteDomain = components["schemas"]["SiteDomain"];
export type AdminSite = components["schemas"]["AdminSiteResponse"];
export type SiteSummary = components["schemas"]["SiteSummaryResponse"];
export type SiteFormRequest = components["schemas"]["SiteFormRequest"];
export type SiteConsentRequest = components["schemas"]["SiteConsentRequest"];
export type SiteConsentResponse = components["schemas"]["SiteConsentResponse"];
export type ReviewAsk = components["schemas"]["ReviewAsk"];
export type ReviewAskSettings = components["schemas"]["ReviewAskSettings"];
export type ReviewAskSettingsUpdate = components["schemas"]["ReviewAskSettingsUpdate"];
export type ReviewAskSummary = components["schemas"]["ReviewAskSummaryResponse"];
export type ReviewAskAction = components["schemas"]["ReviewAskRespondRequest"]["action"];

const SITE = "/admin/site";
const REVIEWS = "/admin/review-asks";
const publicSite = (slug: string) => `/public/sites/${encodeURIComponent(slug)}`;

// ── Visitors (no account) ──────────────────────────────────────────────────

export function fetchPublicSite(slug: string) {
  return apiRequest<PublicSite>(publicSite(slug));
}

export function sendSiteForm(slug: string, kind: "trial" | "contact", form: SiteFormRequest) {
  return apiRequest<{ status: "received" }>(`${publicSite(slug)}/forms/${kind}`, { method: "POST", body: form });
}

export function recordSiteConsent(slug: string, consent: SiteConsentRequest) {
  return apiRequest<SiteConsentResponse>(`${publicSite(slug)}/consents`, { method: "POST", body: consent });
}

// ── Staff ──────────────────────────────────────────────────────────────────

export function getSite(token: string) {
  return apiRequest<AdminSite>(SITE, { token });
}

export async function saveSite(token: string, update: SiteSettingsUpdate) {
  return (await apiRequest<{ settings: SiteSettings }>(SITE, { method: "PUT", token, body: update })).settings;
}

export function getSiteSummary(token: string) {
  return apiRequest<SiteSummary>(`${SITE}/summary`, { token });
}

export async function addSiteDomain(token: string, host: string) {
  return (await apiRequest<{ domain: SiteDomain }>(`${SITE}/domains`, { method: "POST", token, body: { host } })).domain;
}

export async function checkSiteDomain(token: string, id: string) {
  return (await apiRequest<{ domain: SiteDomain }>(`${SITE}/domains/${id}/check`, { method: "POST", token })).domain;
}

export async function makeSiteDomainPrimary(token: string, id: string) {
  return (await apiRequest<{ domain: SiteDomain }>(`${SITE}/domains/${id}/primary`, { method: "PUT", token })).domain;
}

export function removeSiteDomain(token: string, id: string) {
  return apiRequest<void>(`${SITE}/domains/${id}`, { method: "DELETE", token });
}

export async function getReviewAskSettings(token: string) {
  return (await apiRequest<{ settings: ReviewAskSettings }>(`${REVIEWS}/settings`, { token })).settings;
}

export async function saveReviewAskSettings(token: string, update: ReviewAskSettingsUpdate) {
  return (
    await apiRequest<{ settings: ReviewAskSettings }>(`${REVIEWS}/settings`, { method: "PUT", token, body: update })
  ).settings;
}

export function getReviewAskSummary(token: string) {
  return apiRequest<ReviewAskSummary>(`${REVIEWS}/summary`, { token });
}

// ── Members ────────────────────────────────────────────────────────────────

export async function fetchReviewAsk(token: string) {
  return (await apiRequest<{ ask: ReviewAsk | null }>("/me/review-ask", { token })).ask;
}

export async function respondToReviewAsk(token: string, id: string, action: ReviewAskAction) {
  return (
    await apiRequest<{ ask: ReviewAsk | null }>(`/me/review-asks/${id}/respond`, { method: "POST", token, body: { action } })
  ).ask;
}

export async function setReviewAskOptOut(token: string, optedOut: boolean) {
  return (
    await apiRequest<{ opted_out: boolean }>("/me/review-asks/opt-out", { method: optedOut ? "PUT" : "DELETE", token })
  ).opted_out;
}
