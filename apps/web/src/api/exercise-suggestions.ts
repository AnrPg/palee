import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/** ADR-461: suggestions for an exercise name being typed. */
export type ExerciseSuggestionSource = components["schemas"]["ExerciseSuggestionGroup"]["source"];
export type ExerciseSuggestion = components["schemas"]["ExerciseSuggestion"];
export type ExerciseSuggestionGroup = { source: ExerciseSuggestionSource; items: ExerciseSuggestion[] };

const SOURCES: ExerciseSuggestionSource[] = ["mine", "box", "palee"];

/**
 * The groups of an answer, in the fixed order mine, box, palee. Anything
 * malformed (an older server, a stub answering `{}`) is dropped, never thrown.
 */
export function normalizeExerciseSuggestions(body: unknown): ExerciseSuggestionGroup[] {
  const groups = (body as { groups?: unknown } | null)?.groups;
  if (!Array.isArray(groups)) return [];
  const out: ExerciseSuggestionGroup[] = [];
  for (const source of SOURCES) {
    const group = groups.find((g) => (g as { source?: unknown } | null)?.source === source) as { items?: unknown } | undefined;
    const items = Array.isArray(group?.items)
      ? group.items.flatMap((raw): ExerciseSuggestion[] => {
          const item = raw as Partial<ExerciseSuggestion> | null;
          if (!item || typeof item.name !== "string" || !item.name.trim()) return [];
          return [
            {
              name: item.name,
              catalog_slug: typeof item.catalog_slug === "string" ? item.catalog_slug : null,
              hint: typeof item.hint === "string" ? item.hint : null,
              uses_count: typeof item.uses_count === "number" ? item.uses_count : 0,
            },
          ];
        })
      : [];
    if (items.length) out.push({ source, items });
  }
  return out;
}

export async function fetchExerciseSuggestions(
  token: string,
  params: { q: string; organizationId?: string | null; limit?: number },
  signal?: AbortSignal,
): Promise<ExerciseSuggestionGroup[]> {
  const search = new URLSearchParams({ q: params.q });
  if (params.organizationId) search.set("organization_id", params.organizationId);
  if (params.limit) search.set("limit", String(params.limit));
  const body = await apiRequest<unknown>(`/me/exercise-suggestions?${search.toString()}`, {
    token,
    signal,
    scope: "account",
  });
  return normalizeExerciseSuggestions(body);
}

/** ADR-461: the Palee team's review of typed names (vendor console). */
export type ExerciseNameCandidate = components["schemas"]["ExerciseNameCandidate"];
export type ExerciseCandidateQueue = components["schemas"]["ExerciseNameCandidateQueue"];
export type ExerciseCandidateDecision = components["schemas"]["ExerciseNameCandidateDecision"];

export async function fetchExerciseCandidates(token: string, status: ExerciseNameCandidate["status"], minOwners: number) {
  const body = await apiRequest<Partial<ExerciseCandidateQueue>>(
    `/platform/exercise-candidates?status=${status}&min_owners=${minOwners}`,
    { token, scope: "account" },
  );
  return {
    candidates: Array.isArray(body?.candidates) ? body.candidates : [],
    catalog: Array.isArray(body?.catalog) ? body.catalog : [],
  };
}

export async function decideExerciseCandidate(token: string, id: string, decision: ExerciseCandidateDecision) {
  return apiRequest<components["schemas"]["ExerciseNameCandidateDecided"]>(`/platform/exercise-candidates/${id}/decision`, {
    method: "POST",
    token,
    body: decision,
    scope: "account",
  });
}
