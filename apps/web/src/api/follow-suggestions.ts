import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";
import type { FollowStatus } from "@/api/social";

/**
 * «Ίσως γνωρίζεις» (ADR-561): people to follow, each with one reason. The
 * key sits outside `SOCIAL_KEY` on purpose: following someone from a card
 * must not refetch the list and pull the card from under the finger.
 */
export type FollowSuggestion = components["schemas"]["FollowSuggestion"];
export type FollowSuggestionReason = FollowSuggestion["reason"];
export type FollowSuggestionKind = FollowSuggestionReason["kind"];

export const FOLLOW_SUGGESTIONS_KEY = ["follow-suggestions"] as const;
export const followSuggestionsKey = (seed: string | null = null) => [...FOLLOW_SUGGESTIONS_KEY, seed ?? "all"] as const;

export function fetchFollowSuggestions(token: string, seed: string | null = null) {
  const query = seed ? `?${new URLSearchParams({ seed })}` : "";
  return apiRequest<{ people: FollowSuggestion[] }>(`/me/follow-suggestions${query}`, { token });
}

/** Follows (a request when private) and counts it for the reason shown. */
export async function followSuggested(token: string, id: string, reason: FollowSuggestionKind) {
  const data = await apiRequest<{ status: FollowStatus }>(`/me/follow-suggestions/${id}/follow`, {
    method: "POST",
    token,
    body: { reason },
  });
  return data.status;
}

/** ✕: not suggested again unless they start following you. */
export function dismissSuggestion(token: string, id: string, reason: FollowSuggestionKind) {
  return apiRequest<void>(`/me/follow-suggestions/${id}/dismiss`, { method: "POST", token, body: { reason } });
}

export function undismissSuggestion(token: string, id: string) {
  return apiRequest<void>(`/me/follow-suggestions/${id}/dismiss`, { method: "DELETE", token });
}
