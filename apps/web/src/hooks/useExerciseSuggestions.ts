"use client";

import { keepPreviousData, useQuery } from "@tanstack/react-query";

import { SELECTED_ORGANIZATION_SLUG_KEY } from "@/api/client";
import { fetchExerciseSuggestions, type ExerciseSuggestionGroup } from "@/api/exercise-suggestions";
import { fetchOrganizationMemberships, type OrganizationMembership } from "@/api/organizations";
import { useOptionalSession } from "@/components/session-provider";
import { useDebounced } from "@/hooks/useDebounced";
import { ORGANIZATION_MEMBERSHIPS_KEY } from "@/lib/organization-slug";
import { FRESHNESS } from "@/lib/query-policy";
import { fuzzy, type FuzzyMatch } from "@/lib/structured-plan/fuzzy";

/** Debounce of the server query while someone types (ADR-461). */
export const EXERCISE_SUGGESTION_DEBOUNCE_MS = 120;
const EMPTY: ExerciseSuggestionGroup[] = [];

/** ADR-215: no token in the key; the organization is part of the answer's scope. */
export const exerciseSuggestionKey = (q: string, organizationId: string | null) =>
  ["exercise-suggestions", organizationId ?? "none", q] as const;

export type RankedExerciseSuggestion = ExerciseSuggestionGroup["items"][number] & {
  source: ExerciseSuggestionGroup["source"];
  marks: FuzzyMatch["marks"];
};

/**
 * Re-ranks the server's groups for what is typed now (the server answered
 * for a slightly older text): within each group best fuzzy match first, the
 * server's order for ties. A server item the client matcher cannot match
 * (a synonym, "σκουατ" → Squat) stays, after the matched ones, unmarked.
 */
export function rankExerciseSuggestions(query: string, groups: ExerciseSuggestionGroup[]): RankedExerciseSuggestion[] {
  const out: RankedExerciseSuggestion[] = [];
  for (const group of groups) {
    const ranked = group.items
      .map((item, index) => ({ item, index, match: fuzzy(query, item.name) }))
      .sort((a, b) => (b.match?.score ?? -1) - (a.match?.score ?? -1) || a.index - b.index);
    for (const { item, match } of ranked) out.push({ ...item, source: group.source, marks: match?.marks ?? [] });
  }
  return out;
}

/**
 * Exercise-name suggestions for `text` (ADR-461): the person's own names, the
 * box's (the selected box unless `organizationId` is given) and Palee's.
 * Debounced, stale requests aborted (react-query's signal), previous answer
 * kept while the next one loads. Fewer than two letters ask nothing.
 */
export function useExerciseSuggestions(text: string, options: { organizationId?: string | null; enabled?: boolean; limit?: number } = {}) {
  const session = useOptionalSession();
  const token = session?.tokens?.access_token ?? null;
  const selectedOrganizationId = useSelectedOrganizationId(options.organizationId === undefined);
  const organizationId = options.organizationId !== undefined ? options.organizationId : selectedOrganizationId;
  const q = useDebounced(text.trim(), EXERCISE_SUGGESTION_DEBOUNCE_MS);
  const enabled = (options.enabled ?? true) && Boolean(token) && q.length >= 2;
  const query = useQuery({
    queryKey: exerciseSuggestionKey(q, organizationId),
    enabled,
    queryFn: ({ signal }) => fetchExerciseSuggestions(token!, { q, organizationId, limit: options.limit }, signal),
    placeholderData: keepPreviousData,
    staleTime: 30_000,
  });
  return { groups: enabled ? (query.data ?? EMPTY) : EMPTY, isFetching: query.isFetching };
}

/**
 * The selected box's id: the `/org/:slug` of the page, else the remembered
 * selection, else the first membership (the shared memberships cache entry).
 * Works outside the app's providers too (no session: no box).
 */
function useSelectedOrganizationId(wanted: boolean): string | null {
  const session = useOptionalSession();
  const token = session?.tokens?.access_token ?? null;
  const userId = session?.currentUser?.id ?? null;
  const memberships = useQuery({
    queryKey: [...ORGANIZATION_MEMBERSHIPS_KEY, userId],
    enabled: wanted && session?.status === "authenticated" && Boolean(token && userId),
    queryFn: () => fetchOrganizationMemberships(token!),
    staleTime: FRESHNESS.account,
  });
  const list: OrganizationMembership[] = Array.isArray(memberships.data) ? memberships.data : [];
  if (!wanted || list.length === 0) return null;
  const slug = selectedSlug();
  const membership = (slug ? list.find((m) => m.organization?.slug === slug) : null) ?? list[0];
  return membership?.organization?.id ?? null;
}

function selectedSlug(): string | null {
  if (typeof window === "undefined") return null;
  const fromPath = window.location.pathname.match(/^\/org\/([^/]+)/)?.[1];
  if (fromPath) return fromPath;
  try {
    return window.localStorage.getItem(SELECTED_ORGANIZATION_SLUG_KEY);
  } catch {
    return null;
  }
}
