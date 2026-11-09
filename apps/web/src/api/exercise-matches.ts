import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/** ADR-570: an exercise the matcher found in a free-text workout, for the coach to confirm. */
export type ExerciseMatch = components["schemas"]["ExerciseMatch"];
export type ExerciseMatchDecision = components["schemas"]["ExerciseMatchDecisions"]["decisions"][number];

/** The saved draft's matches; anything malformed (an older server, a stub answering `{}`) is no match. */
export async function fetchExerciseMatches(token: string, workoutId: string): Promise<ExerciseMatch[]> {
  const body = await apiRequest<{ matches?: unknown }>(`/admin/workouts/${workoutId}/exercise-matches`, { token });
  const matches = body?.matches;
  if (!Array.isArray(matches)) return [];
  return matches.filter(
    (match): match is ExerciseMatch =>
      Boolean(match) &&
      typeof match.id === "string" &&
      typeof match.typed === "string" &&
      typeof match.exercise_ref === "string" &&
      typeof match.line === "number" &&
      typeof match.from === "number" &&
      typeof match.to === "number",
  );
}

export async function decideExerciseMatches(token: string, workoutId: string, decisions: ExerciseMatchDecision[]) {
  return apiRequest<components["schemas"]["ExerciseMatchesDecided"]>(`/admin/workouts/${workoutId}/exercise-matches/decisions`, {
    method: "POST",
    token,
    body: { decisions },
  });
}
