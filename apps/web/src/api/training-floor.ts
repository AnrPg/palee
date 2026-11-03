import { apiRequest } from "@/api/client";
import type { ProgressRange } from "@/api/account-training";
import type { operations } from "@/api/generated/schema";

// v3.1 «Training and floor» (ADR-356..359, ADR-389): WOD leaderboard filters
// and percentiles, the leaderboard profile, WOD snapshots, the fitness
// profile, visit badges and one booking as a calendar invite.

type Json<T> = T extends { content: { "application/json": infer Body } } ? Body : never;
type Op = operations;

export type WorkoutLeaderboard = Json<Op["PaleeWeb.WorkoutLeaderboardController.show"]["responses"][200]>;
export type WorkoutLeaderboardRow = WorkoutLeaderboard["rows"][number];
export type LeaderboardQuery = NonNullable<Op["PaleeWeb.WorkoutLeaderboardController.show"]["parameters"]["query"]>;
export type LeaderboardWindow = NonNullable<LeaderboardQuery["window"]>;
export type AgeGroup = NonNullable<LeaderboardQuery["age_group"]>;
export type Division = NonNullable<LeaderboardQuery["division"]>;
export type LeaderboardProfile = Json<Op["PaleeWeb.WorkoutLeaderboardController.profile"]["responses"][200]>;
export type LeaderboardProfileRequest = Json<
  NonNullable<Op["PaleeWeb.WorkoutLeaderboardController.update_profile"]["requestBody"]>
>;
export type WorkoutSnapshot = Json<Op["PaleeWeb.WorkoutSnapshotController.show"]["responses"][200]>["snapshot"];
export type WorkoutAsPerformed = Json<Op["PaleeWeb.WorkoutSnapshotController.execution"]["responses"][200]>;
export type FitnessProfile = Json<Op["PaleeWeb.FitnessProfileController.show"]["responses"][200]>;
export type FitnessDomain = FitnessProfile["domains"][number];
export type FitnessDomainName = FitnessDomain["domain"];
export type FitnessReason = NonNullable<FitnessDomain["reasons"]>[number];
export type FitnessFocus = FitnessProfile["focus"][number];
export type FitnessSettings = FitnessProfile["settings"];
export type FitnessDisplayMode = FitnessSettings["display"];
export type FitnessSettingsRequest = Json<NonNullable<Op["PaleeWeb.FitnessProfileController.update_settings"]["requestBody"]>>;
export type ClassVisitBadges = Json<Op["PaleeWeb.AdminVisitBadgesController.show"]["responses"][200]>;
export type ClassVisitPerson = ClassVisitBadges["people"][number];
export type VisitBadge = ClassVisitPerson["badges"][number];
export type VisitVia = NonNullable<ClassVisitPerson["via"]>;
export type PaleeConsent = Json<Op["PaleeWeb.PaleeLeaderboardConsentController.show"]["responses"][200]>;
export type PaleeChoice = NonNullable<PaleeConsent["choice"]>;

const org = (slug: string) => `/org/${encodeURIComponent(slug)}`;

export const leaderboardKey = (slug: string, workoutId: string, query: LeaderboardQuery) =>
  ["training-floor", "leaderboard", slug, workoutId, query] as const;
export const leaderboardProfileKey = (slug: string) => ["training-floor", "leaderboard-profile", slug] as const;
export const asPerformedKey = (slug: string, kind: "execution" | "training_log", id: string) =>
  ["training-floor", "as-performed", slug, kind, id] as const;
export const fitnessProfileKeys = ["training-floor", "fitness-profile"] as const;
export const fitnessProfileKey = (division: Division | null, period: ProgressRange) =>
  [...fitnessProfileKeys, division, period] as const;
export const visitBadgesKey = (slotId: string) => ["training-floor", "visit-badges", slotId] as const;
export const paleeConsentKey = ["training-floor", "palee-consent"] as const;

/** ADR-356: the query string of a filtered leaderboard, without empty filters. */
export function leaderboardSearch(query: LeaderboardQuery) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value === undefined || value === null || value === "" || value === false) continue;
    params.set(key, String(value));
  }
  const text = params.toString();
  return text ? `?${text}` : "";
}

export function fetchWorkoutLeaderboard(token: string, slug: string, workoutId: string, query: LeaderboardQuery) {
  return apiRequest<WorkoutLeaderboard>(
    `${org(slug)}/workouts/${encodeURIComponent(workoutId)}/leaderboard${leaderboardSearch(query)}`,
    { token },
  );
}

export function fetchLeaderboardProfile(token: string, slug: string) {
  return apiRequest<LeaderboardProfile>(`${org(slug)}/me/leaderboard-profile`, { token });
}

export function updateLeaderboardProfile(token: string, slug: string, body: LeaderboardProfileRequest) {
  return apiRequest<LeaderboardProfile>(`${org(slug)}/me/leaderboard-profile`, { method: "PUT", token, body });
}

/** ADR-389: the WOD as one's own run or score performed it, and whether it changed since. */
export function fetchWorkoutAsPerformed(token: string, slug: string, kind: "execution" | "training_log", id: string) {
  const path =
    kind === "execution"
      ? `${org(slug)}/me/executions/${encodeURIComponent(id)}/workout-snapshot`
      : `${org(slug)}/me/training-log/entries/${encodeURIComponent(id)}/workout-snapshot`;
  return apiRequest<WorkoutAsPerformed>(path, { token });
}

/**
 * ADR-358/395: account level, own data only. Without a division the standards
 * are neutral. `period` is Πρόοδος's period bar: each domain then says how it
 * moved since the period started (`all`: no change).
 */
export function fetchFitnessProfile(token: string, division: Division | null, period: ProgressRange = "all") {
  const params = new URLSearchParams();
  if (division) params.set("division", division);
  if (period !== "all") params.set("period", period);
  const query = params.toString();
  return apiRequest<FitnessProfile>(`/me/fitness-profile${query ? `?${query}` : ""}`, { token, scope: "account" });
}

/** ADR-395: body weight, birth year and what the card shows (account level, private). */
export function putFitnessSettings(token: string, body: FitnessSettingsRequest) {
  return apiRequest<FitnessSettings>("/me/fitness-profile/settings", { method: "PUT", token, scope: "account", body });
}

/** ADR-394: my answer about the Palee-wide benchmark board (account level). */
export function fetchPaleeConsent(token: string) {
  return apiRequest<PaleeConsent>("/me/palee-leaderboard", { token, scope: "account" });
}

export function putPaleeConsent(token: string, choice: PaleeChoice) {
  return apiRequest<PaleeConsent>("/me/palee-leaderboard", { method: "PUT", token, scope: "account", body: { choice } });
}

/** Withdraw: off every Palee-wide board at once; the next tap asks again. */
export function withdrawPaleeConsent(token: string) {
  return apiRequest<PaleeConsent>("/me/palee-leaderboard", { method: "DELETE", token, scope: "account" });
}

/** ADR-359: who is new in one class (the selected box). */
export function fetchClassVisitBadges(token: string, slotId: string) {
  return apiRequest<ClassVisitBadges>(`/admin/schedule/slots/${encodeURIComponent(slotId)}/visit-badges`, { token });
}

/** ADR-359: one booking as an .ics invite, with the same UID as the calendar feed. */
export function fetchBookingInvite(token: string, slug: string, bookingId: string) {
  return apiRequest<Blob>(`${org(slug)}/bookings/${encodeURIComponent(bookingId)}/calendar.ics`, {
    token,
    responseType: "blob",
  });
}
