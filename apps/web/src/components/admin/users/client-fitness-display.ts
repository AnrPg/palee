import type { ClientFitnessDisplay, FitnessDisplayOverride } from "@/api/staff";

/**
 * ADR-395: what a coach picks for a client's «Επίπεδο φυσικής κατάστασης».
 * `client` leaves the client's own choice (no override); the other two are
 * the override the client's card then marks «Το όρισε ο coach σου».
 */
export type CoachFitnessChoice = "client" | FitnessDisplayOverride;
export type FitnessDisplay = "all" | FitnessDisplayOverride;

const STRICTNESS: Record<FitnessDisplay, number> = { all: 0, progress_only: 1, none: 2 };

/** The client's own choice; a client who set nothing sees everything. */
export function clientOwnDisplay(view: ClientFitnessDisplay | undefined): FitnessDisplay {
  return view?.settings?.display ?? "all";
}

export function coachChoice(view: ClientFitnessDisplay | undefined): CoachFitnessChoice {
  return view?.override ?? "client";
}

export function overrideFor(choice: CoachFitnessChoice): FitnessDisplayOverride | null {
  return choice === "client" ? null : choice;
}

/**
 * The strictest choice wins (all < progress_only < none), so a coach's
 * choice looser than the client's own changes nothing on the card.
 */
export function clientChoiceWins(view: ClientFitnessDisplay | undefined, choice: CoachFitnessChoice): boolean {
  if (choice === "client") return false;
  return STRICTNESS[clientOwnDisplay(view)] > STRICTNESS[choice];
}

/** Body weight and birth year, or null when the client filled in neither. */
export function personalFacts(view: ClientFitnessDisplay | undefined): { weightKg: number | null; birthYear: number | null } | null {
  const weightKg = view?.settings?.body_weight_kg ?? null;
  const birthYear = view?.settings?.birth_year ?? null;
  if (weightKg === null && birthYear === null) return null;
  return { weightKg, birthYear };
}

/**
 * The panel is for the client's coach only: a client's profile, a viewer
 * with the coach role who may read client training. The API still answers
 * 403 not_your_client without an active coaching relationship, and the panel
 * then shows nothing (weight and birth year are personal).
 */
export function showsClientFitnessDisplay({ isClient, actorCoaches, canViewClientTraining }: { isClient: boolean; actorCoaches: boolean; canViewClientTraining: boolean }): boolean {
  return isClient && actorCoaches && canViewClientTraining;
}
