import { apiRequest } from "@/api/client";
import type { OnlinePayment } from "@/api/my-payments";
import type { components } from "@/api/generated/schema";

/**
 * Training programmes (ADR-370/371, CP-D4): a box or a coach writes a
 * multi-week plan from its own WODs and sells it. Staff calls go through the
 * selected box (`/admin`); a buyer always calls the seller's box by its slug
 * (`/org/:slug/me`), so buying from another box never needs switching boxes;
 * the catalogue and a box's programmes are public.
 */
export type StaffProgramme = components["schemas"]["StaffProgramme"];
export type ProgrammeVersion = components["schemas"]["ProgrammeVersion"];
export type ProgrammeInput = components["schemas"]["ProgrammeInput"];
export type ProgrammeDay = NonNullable<ProgrammeInput["draft_days"]>[number];
export type ProgrammePurchase = components["schemas"]["ProgrammePurchase"];
export type ProgrammeReview = components["schemas"]["ProgrammeReview"];
export type PublicProgramme = components["schemas"]["PublicProgramme"];
export type MarketplaceProgramme = components["schemas"]["MarketplaceProgramme"];
export type ProgrammeTerms = components["schemas"]["ProgrammeTerms"];
export type ProgrammeLevel = NonNullable<ProgrammeInput["level"]>;
export type ProgrammeGoal = NonNullable<ProgrammeInput["goal"]>;
export type ProgrammeListing = NonNullable<ProgrammeInput["listing"]>;
export type ProgrammeRefundPolicy = NonNullable<ProgrammeInput["refund_policy"]>;
export type ProgrammeHideReason = NonNullable<components["schemas"]["ProgrammeReviewModeration"]["hidden_reason"]>;
/** The box's public card next to its programmes (name, slug, logo, city). */
export type ProgrammeBox = { name?: string; slug?: string; logo_url?: string | null; city?: string | null } & Record<string, unknown>;

export const PROGRAMME_REFUND_POLICIES: ProgrammeRefundPolicy[] = ["before_start", "withdrawal_only", "pro_rata"];
export const PROGRAMME_HIDE_REASONS: ProgrammeHideReason[] = ["abuse", "personal_data", "off_topic", "spam"];

export const STAFF_PROGRAMMES_KEY = ["admin", "programmes"] as const;
export const staffProgrammeKey = (id: string) => ["admin", "programmes", id] as const;
export const programmePurchasesKey = (id: string) => ["admin", "programmes", id, "purchases"] as const;
export const programmeReviewsKey = (id: string) => ["admin", "programmes", id, "reviews"] as const;
export const myProgrammesKey = (slug: string) => ["programmes", "mine", slug] as const;
export const myProgrammeKey = (slug: string, id: string) => ["programmes", "mine", slug, id] as const;

const id = (value: string) => encodeURIComponent(value);
const me = (slug: string) => `/org/${id(slug)}/me`;

// Staff -------------------------------------------------------------------

export async function fetchStaffProgrammes(token: string) {
  const data = await apiRequest<{ programmes?: StaffProgramme[] }>("/admin/programmes", { token });
  return data.programmes ?? [];
}

export async function fetchStaffProgramme(token: string, programmeId: string) {
  const data = await apiRequest<{ programme: StaffProgramme }>(`/admin/programmes/${id(programmeId)}`, { token });
  return data.programme;
}

export async function createProgramme(token: string, body: ProgrammeInput) {
  const data = await apiRequest<{ programme: StaffProgramme }>("/admin/programmes", { method: "POST", token, body });
  return data.programme;
}

export async function updateProgramme(token: string, programmeId: string, body: ProgrammeInput) {
  const data = await apiRequest<{ programme: StaffProgramme }>(`/admin/programmes/${id(programmeId)}`, {
    method: "PATCH",
    token,
    body,
  });
  return data.programme;
}

export async function publishProgramme(token: string, programmeId: string, changelog?: string | null) {
  const data = await apiRequest<{ programme: StaffProgramme }>(`/admin/programmes/${id(programmeId)}/publish`, {
    method: "POST",
    token,
    body: changelog ? { changelog } : {},
  });
  return data.programme;
}

export async function setProgrammeArchived(token: string, programmeId: string, archived: boolean) {
  const data = await apiRequest<{ programme: StaffProgramme }>(
    `/admin/programmes/${id(programmeId)}/${archived ? "archive" : "restore"}`,
    { method: "POST", token },
  );
  return data.programme;
}

export async function fetchProgrammePurchases(token: string, programmeId: string) {
  const data = await apiRequest<{ purchases?: ProgrammePurchase[] }>(`/admin/programmes/${id(programmeId)}/purchases`, { token });
  return data.purchases ?? [];
}

export async function refundProgrammePurchase(
  token: string,
  purchaseId: string,
  body: { amount_cents: number; reason?: string; idempotency_key: string },
) {
  return apiRequest<{ purchase: ProgrammePurchase }>(`/admin/programme-purchases/${id(purchaseId)}/refund`, {
    method: "POST",
    token,
    body,
  });
}

export async function fetchProgrammeReviews(token: string, programmeId: string) {
  const data = await apiRequest<{ reviews?: ProgrammeReview[] }>(`/admin/programmes/${id(programmeId)}/reviews`, { token });
  return data.reviews ?? [];
}

export async function moderateProgrammeReview(token: string, reviewId: string, hiddenReason: ProgrammeHideReason | null) {
  const data = await apiRequest<{ review: ProgrammeReview }>(`/admin/programme-reviews/${id(reviewId)}/moderate`, {
    method: "POST",
    token,
    body: { hidden_reason: hiddenReason },
  });
  return data.review;
}

// Public ------------------------------------------------------------------

export type CatalogueFilters = { query?: string; goal?: ProgrammeGoal | null; level?: ProgrammeLevel | null; offset?: number };

export async function fetchProgrammeCatalogue(filters: CatalogueFilters = {}) {
  const params = new URLSearchParams();
  if (filters.query?.trim()) params.set("query", filters.query.trim());
  if (filters.goal) params.set("goal", filters.goal);
  if (filters.level) params.set("level", filters.level);
  if (filters.offset) params.set("offset", String(filters.offset));
  const query = params.toString();
  const data = await apiRequest<{ programmes?: MarketplaceProgramme[] }>(`/public/programmes${query ? `?${query}` : ""}`, {
    scope: "account",
  });
  return data.programmes ?? [];
}

export async function fetchBoxProgrammes(slug: string) {
  const data = await apiRequest<{ box: ProgrammeBox; programmes?: PublicProgramme[] }>(`/public/boxes/${id(slug)}/programmes`, {
    scope: "account",
  });
  return { box: data.box, programmes: data.programmes ?? [] };
}

export async function fetchPublicProgramme(slug: string, programmeId: string) {
  return apiRequest<{ box: ProgrammeBox; programme: PublicProgramme }>(
    `/public/boxes/${id(slug)}/programmes/${id(programmeId)}`,
    { scope: "account" },
  );
}

// Buyer -------------------------------------------------------------------

export async function fetchProgrammeTerms(token: string, slug: string, programmeId: string, language: "el" | "en") {
  return apiRequest<ProgrammeTerms>(`${me(slug)}/programmes/${id(programmeId)}/purchase-terms?language=${language}`, { token });
}

export async function buyProgramme(
  token: string,
  slug: string,
  programmeId: string,
  body: { idempotency_key: string; starts_on: string; start_now?: boolean; language: "el" | "en" },
) {
  return apiRequest<{ purchase_id: string; payment: OnlinePayment }>(`${me(slug)}/programmes/${id(programmeId)}/buy`, {
    method: "POST",
    token,
    body,
  });
}

export async function fetchMyProgrammes(token: string, slug: string) {
  const data = await apiRequest<{ purchases?: ProgrammePurchase[] }>(`${me(slug)}/programme-purchases`, { token });
  return data.purchases ?? [];
}

export async function fetchMyProgramme(token: string, slug: string, purchaseId: string) {
  const data = await apiRequest<{ purchase: ProgrammePurchase }>(`${me(slug)}/programme-purchases/${id(purchaseId)}`, { token });
  return data.purchase;
}

export async function withdrawProgramme(token: string, slug: string, purchaseId: string) {
  return apiRequest<{ purchase: ProgrammePurchase; rule?: string | null }>(
    `${me(slug)}/programme-purchases/${id(purchaseId)}/withdraw`,
    { method: "POST", token },
  );
}

export async function reviewProgramme(token: string, slug: string, purchaseId: string, body: { rating: number; body?: string | null }) {
  const data = await apiRequest<{ review: ProgrammeReview }>(`${me(slug)}/programme-purchases/${id(purchaseId)}/review`, {
    method: "POST",
    token,
    body,
  });
  return data.review;
}
