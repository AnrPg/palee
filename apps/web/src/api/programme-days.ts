import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";
import { myProgrammeKey } from "@/api/programmes";

/**
 * A bought programme as a sequence of days (ADR-540): each day's status, the
 * progress, and the earliest day left behind with «Κάν' τη σήμερα» and
 * «Παράλειψη». The buyer always calls the seller's box by its slug.
 */
export type ProgrammePurchaseDays = components["schemas"]["ProgrammePurchaseDays"];
export type ProgrammeBuyerDay = components["schemas"]["ProgrammeBuyerDay"];
export type ProgrammeBuyerDayWorkout = components["schemas"]["ProgrammeBuyerDayWorkout"];
export type ProgrammeBehindDay = components["schemas"]["ProgrammeBehindDay"];
export type ProgrammePurchaseProgress = components["schemas"]["ProgrammePurchaseProgress"];
export type ProgrammeDayStatus = ProgrammeBuyerDay["status"];

/** Under the purchase's own key, so refreshing the purchase refreshes its days too. */
export const programmeDaysKey = (slug: string, purchaseId: string) => [...myProgrammeKey(slug, purchaseId), "days"] as const;

const path = (slug: string, purchaseId: string) =>
  `/org/${encodeURIComponent(slug)}/me/programme-purchases/${encodeURIComponent(purchaseId)}/days`;

export async function fetchProgrammeDays(token: string, slug: string, purchaseId: string) {
  return apiRequest<ProgrammePurchaseDays>(path(slug, purchaseId), { token });
}

/** «Κάν' τη σήμερα»: moves a behind day (and the days after it) to today. */
export async function doProgrammeDayToday(token: string, slug: string, purchaseId: string, day: number) {
  return apiRequest<ProgrammePurchaseDays>(`${path(slug, purchaseId)}/do-today`, { method: "POST", token, body: { day } });
}

/** «Παράλειψη»: marks a behind day skipped; nothing moves. */
export async function skipProgrammeDay(token: string, slug: string, purchaseId: string, day: number) {
  return apiRequest<ProgrammePurchaseDays>(`${path(slug, purchaseId)}/skip`, { method: "POST", token, body: { day } });
}
