import type { BusinessFeature, BusinessFeatureMap } from "@/api/business-features";

/**
 * ADR-470: the one rule every screen uses to hide what depends on a feature
 * the business has not switched on (online or card payments, referrals,
 * promotions, perks, trials, branches, a floor plan, package modules).
 *
 * - While the answer is loading a feature counts as off, so nothing appears
 *   and then vanishes.
 * - If the answer cannot be read a feature counts as on: a network blip must
 *   never hide a list someone has to work through.
 * - A work list (a queue, an alert) also stays while it still holds rows,
 *   even after its feature was turned off: owed rewards or failed charges
 *   are still owed.
 */
export type BusinessFeatureState =
  | { status: "loading" }
  | { status: "error" }
  | { status: "ready"; features: Partial<BusinessFeatureMap> };

export function featureOn(state: BusinessFeatureState | null | undefined, key: BusinessFeature): boolean {
  if (!state || state.status === "loading") return false;
  if (state.status === "error") return true;
  return state.features[key] === true;
}

/** A work list tied to `key`: shown while the feature is on or while it still has rows. */
export function showsWork(
  state: BusinessFeatureState | null | undefined,
  key: BusinessFeature,
  pending: number | null | undefined,
): boolean {
  return featureOn(state, key) || (pending ?? 0) > 0;
}

/** Whether the answer is known (ready or failed), for screens that wait instead of hiding. */
export function featuresSettled(state: BusinessFeatureState | null | undefined): boolean {
  return Boolean(state && state.status !== "loading");
}
