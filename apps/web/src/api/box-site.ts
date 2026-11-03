import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * The box's website (ADR-352..354, ADR-388), Google review asks (ADR-355),
 * the box's in-app reviews (ADR-386) and its Google listing (ADR-387).
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
export type ReviewAskSettingsResponse = components["schemas"]["ReviewAskSettingsResponse"];
export type SiteSection = SiteSettings["section_order"][number];
export type SiteFaqEntry = SiteSettings["faq"][number];
export type BoxReview = components["schemas"]["BoxReview"];
export type GoogleListing = NonNullable<components["schemas"]["GoogleListing"]>;
export type BoxReviews = components["schemas"]["BoxReviewsResponse"];
export type MyBoxReviews = components["schemas"]["MyBoxReviewsResponse"];
export type GooglePlaceMatch = components["schemas"]["GooglePlaceMatch"];
export type SiteDomainStatus = components["schemas"]["SiteDomainStatusResponse"];

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

/** ADR-388: the page behind «Στείλε τις οδηγίες» (no account). */
export function fetchDomainStatus(token: string) {
  return apiRequest<SiteDomainStatus>(`/public/sites/domain-status/${encodeURIComponent(token)}`);
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

/** ADR-388 «Στείλε τις οδηγίες»: email the records to whoever runs the domain. */
export async function sendSiteDomainInstructions(token: string, id: string, email: string) {
  return (await apiRequest<{ sent_to: string }>(`${SITE}/domains/${id}/instructions`, { method: "POST", token, body: { email } })).sent_to;
}

export function getReviewAskSettings(token: string) {
  return apiRequest<ReviewAskSettingsResponse>(`${REVIEWS}/settings`, { token });
}

export function saveReviewAskSettings(token: string, update: ReviewAskSettingsUpdate) {
  return apiRequest<ReviewAskSettingsResponse>(`${REVIEWS}/settings`, { method: "PUT", token, body: update });
}

/** ADR-387: find the box's Google listing by name. */
export async function searchGooglePlaces(token: string, query: string) {
  return (await apiRequest<{ places: GooglePlaceMatch[] }>(`${REVIEWS}/places?q=${encodeURIComponent(query)}`, { token })).places;
}

// ── In-app reviews (ADR-386) ────────────────────────────────────────────────

export const MY_BOX_REVIEWS_KEY = ["me", "box-reviews"] as const;
export const STAFF_BOX_REVIEWS_KEY = ["admin", "box-reviews"] as const;

export function fetchMyBoxReviews(token: string) {
  return apiRequest<MyBoxReviews>("/me/box-reviews", { token });
}

export async function saveMyBoxReview(token: string, review: { rating: number; body: string | null; locale?: string }) {
  return (await apiRequest<{ review: BoxReview }>("/me/box-review", { method: "PUT", token, body: review })).review;
}

export function deleteMyBoxReview(token: string) {
  return apiRequest<void>("/me/box-review", { method: "DELETE", token });
}

export function fetchStaffBoxReviews(token: string) {
  return apiRequest<BoxReviews>("/admin/box-reviews", { token });
}

export async function replyToBoxReview(token: string, id: string, body: string) {
  return (await apiRequest<{ review: BoxReview }>(`/admin/box-reviews/${id}/reply`, { method: "PUT", token, body: { body } })).review;
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
