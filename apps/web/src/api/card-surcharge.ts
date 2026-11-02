import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

/*
 * ADR-340 «Επιβάρυνση κάρτας»: the box's setting under Ρυθμίσεις › Πληρωμές
 * (with what the law of its country allows) and the staff quote for a card
 * on the box's own POS. Calls go through the selected gym
 * (`/org/:slug/admin/payments/surcharge...`).
 */

type Json<Op extends keyof operations, Code extends number = 200> = operations[Op]["responses"] extends Record<
  Code,
  { content: { "application/json": infer Body } }
>
  ? Body
  : never;

type Body<Op extends keyof operations> =
  NonNullable<operations[Op]["requestBody"]> extends { content: { "application/json": infer Payload } } ? Payload : never;

export type SurchargeStatus = Json<"PaleeWeb.AdminCardSurchargeController.show">;
export type SurchargeSettings = SurchargeStatus["settings"];
export type SurchargeLaw = SurchargeStatus["law"];
export type SurchargeChannel = SurchargeSettings["channels"][number];
export type SurchargeUpdate = Body<"PaleeWeb.AdminCardSurchargeController.update">;
export type SurchargeQuoteBody = Body<"PaleeWeb.AdminCardSurchargeController.quote">;
export type SurchargeQuote = Json<"PaleeWeb.AdminCardSurchargeController.quote">;
export type SurchargeCard = NonNullable<SurchargeQuoteBody["card"]>;

export const SURCHARGE_KEY = ["admin", "payments", "surcharge"] as const;

export function fetchSurcharge(token: string) {
  return apiRequest<SurchargeStatus>("/admin/payments/surcharge", { token });
}

export function saveSurcharge(token: string, update: SurchargeUpdate) {
  return apiRequest<SurchargeStatus>("/admin/payments/surcharge", { method: "PUT", token, body: update });
}

/** What a card on the box's own POS (`desk`) adds to `amount_cents`; `card` null asks only whether the question applies. */
export function quoteSurcharge(token: string, body: SurchargeQuoteBody) {
  return apiRequest<SurchargeQuote>("/admin/payments/surcharge/quote", { method: "POST", token, body });
}
