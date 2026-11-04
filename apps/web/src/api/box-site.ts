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
export type MyBoxReview = NonNullable<MyBoxReviews["mine"]>;
export type BoxReviewModeration = NonNullable<MyBoxReview["moderation"]>;
export type BoxReviewReportRequest = components["schemas"]["BoxReviewReportRequest"];
export type BoxReviewReportReason = BoxReviewReportRequest["reason"];
export type GooglePlaceMatch = components["schemas"]["GooglePlaceMatch"];
export type SiteDomainStatus = components["schemas"]["SiteDomainStatusResponse"];
export type SiteLanguages = components["schemas"]["SiteLanguages"];
export type SiteTranslations = components["schemas"]["SiteTranslationsResponse"];
export type SiteTranslationItem = components["schemas"]["SiteTranslationItem"];
export type SiteTranslationStatus = SiteTranslationItem["status"];
export type SiteTranslationEdit = components["schemas"]["SiteTranslationEdit"];

// ── ADR-530: templates, palettes, draft and publish ─────────────────────────
// These shapes mirror the API (ADR-530). Until the generated schema carries
// them they are spelled out here; once it does, the intersections are no-ops.
export type SiteTemplateKey = "arena" | "tiles" | "stories" | "atelier";
export type SitePaletteKey = "palee" | "electric" | "flame" | "sun" | "amber" | "emerald" | "aegean" | "violet" | "fuchsia" | "olive" | "navy" | "mono";
export type SiteAppearance = "auto" | "light" | "dark";
export type SiteLook = { template: SiteTemplateKey; palette: SitePaletteKey; appearance: SiteAppearance; calm_motion: boolean };
export type SitePhoto = { id: string; url: string; width: number | null; height: number | null; caption: string | null };
export type SitePhotos = { items: SitePhoto[]; video: { url: string; poster_url: string | null } | null };
/** Aggregates only; a null or zero number is not shown. */
export type SiteStats = { classes_per_week: number | null; prs_this_year: number | null; years_open: number | null };
export type SiteProgramme = { id: string; title: string; summary: string | null; weeks: number | null; price_cents: number | null; currency: string | null; cover_url: string | null; url: string | null; sessions_per_week: number | null; level: string | null; rating_average: number | null; rating_count: number };
export type PublicSiteV2 = PublicSite & SiteLook & { photos: SitePhotos; stats: SiteStats | null; programmes: SiteProgramme[]; phone?: string | null };
/** The fields that go live only with «Δημοσίευση». */
export type SiteDraft = Partial<SiteLook & Pick<SiteSettings, "hidden_sections" | "public_schedule" | "public_wod">>;
export type SiteSettingsV2 = SiteSettings & SiteLook & { draft: SiteDraft | null; published_at: string | null; template_notice: boolean };

const SITE = "/admin/site";
const REVIEWS = "/admin/review-asks";
const publicSite = (slug: string) => `/public/sites/${encodeURIComponent(slug)}`;

// ── Visitors (no account) ──────────────────────────────────────────────────

/** ADR-520: `lang` picks one of the site's translations. */
export function fetchPublicSite(slug: string, lang?: string | null) {
  return apiRequest<PublicSite>(`${publicSite(slug)}${lang ? `?lang=${encodeURIComponent(lang)}` : ""}`);
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

export function saveSite(token: string, update: SiteSettingsUpdate) {
  return apiRequest<{ settings: SiteSettings; languages: SiteLanguages }>(SITE, { method: "PUT", token, body: update });
}

// ── Translations (ADR-520) ──────────────────────────────────────────────────

export const siteTranslationsKey = (locale: string) => ["admin", "site", "translations", locale] as const;

export function fetchSiteTranslations(token: string, locale: string) {
  return apiRequest<SiteTranslations>(`${SITE}/translations?locale=${encodeURIComponent(locale)}`, { token });
}

/** A person's texts; an empty text removes the translation. */
export function saveSiteTranslations(token: string, locale: string, entries: SiteTranslationEdit[]) {
  return apiRequest<SiteTranslations>(`${SITE}/translations`, { method: "PUT", token, body: { locale, entries } });
}

/** «Εντάξει, κράτα το»: keep machine or out-of-date texts as they are. */
export function keepSiteTranslations(token: string, locale: string, keys: string[]) {
  return apiRequest<SiteTranslations>(`${SITE}/translations/keep`, { method: "POST", token, body: { locale, keys } });
}

/** «Αυτόματη μετάφραση»: a machine fills what is missing or out of date. */
export function machineTranslateSite(token: string, locale: string) {
  return apiRequest<SiteTranslations>(`${SITE}/translations/machine`, { method: "POST", token, body: { locale } });
}

/** ADR-530: the draft goes live. */
export function publishSite(token: string) {
  return apiRequest<{ settings: SiteSettingsV2 }>(`${SITE}/publish`, { method: "POST", token });
}

/** ADR-530: «Απόρριψη αλλαγών». */
export function discardSiteDraft(token: string) {
  return apiRequest<{ settings: SiteSettingsV2 }>(`${SITE}/draft`, { method: "DELETE", token });
}

/** ADR-530: the public site as it will look with the draft applied. */
export function fetchSitePreview(token: string, lang?: string | null) {
  return apiRequest<PublicSiteV2>(`${SITE}/preview${lang ? `?lang=${encodeURIComponent(lang)}` : ""}`, { token });
}

/** ADR-530: hides «Η ιστοσελίδα σου πήρε νέα όψη». */
export function dismissSiteNotice(token: string) {
  return apiRequest<{ settings: SiteSettingsV2 }>(`${SITE}/notice`, { method: "DELETE", token });
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

// ── Reports on reviews (ADR-397): the Palee team decides, never the box ────

/** The fixed reasons, in the order the report sheet lists them. */
export const REVIEW_REPORT_REASONS: BoxReviewReportReason[] = ["offensive", "personal_data", "not_genuine", "spam", "illegal", "other"];
export const REVIEW_REPORT_NOTE_MAX = 500;

/** «Παράνομο περιεχόμενο» and «Κάτι άλλο» need a few words; the rest do not. */
export function reportNoteRequired(reason: BoxReviewReportReason | null) {
  return reason === "illegal" || reason === "other";
}

/** A member reports a review of their box; it stays up until the Palee team decides. */
export function reportBoxReview(token: string, id: string, body: BoxReviewReportRequest) {
  return apiRequest<{ review_id: string; status: "open" }>(`/me/box-reviews/${encodeURIComponent(id)}/report`, { method: "POST", token, body });
}

/** The box (staff who reply as the box) reports a review of itself. */
export function reportBoxReviewAsBox(token: string, id: string, body: BoxReviewReportRequest) {
  return apiRequest<{ review_id: string; status: "open" }>(`/admin/box-reviews/${encodeURIComponent(id)}/report`, { method: "POST", token, body });
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
  return (await apiRequest<{ ask: ReviewAsk | null }>("/me/review-ask", { token })).ask ?? null;
}

export async function respondToReviewAsk(token: string, id: string, action: ReviewAskAction) {
  return (
    await apiRequest<{ ask: ReviewAsk | null }>(`/me/review-asks/${id}/respond`, { method: "POST", token, body: { action } })
  ).ask ?? null;
}

export async function setReviewAskOptOut(token: string, optedOut: boolean) {
  return (
    await apiRequest<{ opted_out: boolean }>("/me/review-asks/opt-out", { method: optedOut ? "PUT" : "DELETE", token })
  ).opted_out;
}
