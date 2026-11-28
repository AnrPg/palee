/**
 * ADR-201: one WOD variation for several people at once. Each person is
 * programmed as if they were the only one; these pure rules pick who can be
 * chosen and read the per-person outcome.
 */

import { ApiError } from "@/api/client";
import type { ProgramForUsersResult } from "@/api/admin-users";

/** The most people one request may program (the API refuses more). */
export const GROUP_PROGRAMMING_LIMIT = 50;

export type VariationCandidate = {
  userId: string;
  nickname: string;
  /** Already has their own version of this class (ADR-125). */
  hasVersion: boolean;
};

type BookingLike = {
  user_id: string;
  user_nickname?: string | null;
  status: string;
  guest_name?: string | null;
};

/**
 * The people of a class who can get a variation: approved or pending
 * bookings, each person once, guests left out (a guest has no account of
 * their own; the booking belongs to the host).
 */
export function variationCandidates(
  bookings: readonly BookingLike[],
  memberVersions: readonly { user_id: string }[] = [],
): VariationCandidate[] {
  const withVersion = new Set(memberVersions.map((version) => version.user_id));
  const seen = new Set<string>();
  const candidates: VariationCandidate[] = [];

  for (const booking of bookings) {
    if (booking.status !== "approved" && booking.status !== "pending") continue;
    if (booking.guest_name) continue;
    if (!booking.user_id || seen.has(booking.user_id)) continue;
    seen.add(booking.user_id);
    candidates.push({
      userId: booking.user_id,
      nickname: booking.user_nickname || booking.user_id,
      hasVersion: withVersion.has(booking.user_id),
    });
  }

  return candidates.sort((a, b) => a.nickname.localeCompare(b.nickname));
}

/**
 * The day a class variant is filed under. The API checks the booking within
 * that UTC day, so it is the class's UTC date, not the viewer's local one.
 */
export function classDay(scheduledAt: string): string {
  const date = new Date(scheduledAt);
  return Number.isNaN(date.getTime()) ? scheduledAt.slice(0, 10) : date.toISOString().slice(0, 10);
}

/** Adds or removes one person, never past the limit. */
export function toggleSelection(selected: readonly string[], userId: string, limit = GROUP_PROGRAMMING_LIMIT): string[] {
  if (selected.includes(userId)) return selected.filter((id) => id !== userId);
  if (selected.length >= limit) return [...selected];
  return [...selected, userId];
}

export type GroupOutcomeRow = {
  userId: string;
  nickname: string;
  ok: boolean;
  /** The error as the one-person endpoint would have answered it. */
  error?: ApiError;
};

const ERROR_STATUS: Record<string, number> = {
  not_found: 404,
  slot_not_found: 404,
  workout_not_found: 404,
  not_your_client: 403,
  forbidden: 403,
  programming_not_in_package: 403,
  member_wod_not_covered: 403,
};

/**
 * One row per person, in the order the API answered. A failure carries an
 * ApiError so it is localized with the same keys as a one-person failure.
 */
export function groupOutcomeRows(
  results: readonly ProgramForUsersResult[],
  nicknames: ReadonlyMap<string, string>,
): GroupOutcomeRow[] {
  return results.map((result) => {
    const nickname = nicknames.get(result.user_id) ?? result.user_id;
    if (result.status === "ok") return { userId: result.user_id, nickname, ok: true };

    const code = result.code ?? "unexpected_server_error";
    const status = ERROR_STATUS[code] ?? (code === "unexpected_server_error" ? 500 : 422);
    const error = new ApiError(status, code, {
      code,
      params: (result.params ?? undefined) as Record<string, unknown> | undefined,
    });
    return { userId: result.user_id, nickname, ok: false, error };
  });
}

/** How many people got it and how many did not. */
export function outcomeCounts(rows: readonly GroupOutcomeRow[]) {
  const succeeded = rows.filter((row) => row.ok).length;
  return { succeeded, failed: rows.length - succeeded };
}

/** A box member found by «Ξεχωριστό WOD για άτομα»'s search (ADR-746). */
export type VariationPerson = { userId: string; nickname: string; hasVersion: boolean; booked: boolean };

/**
 * ADR-746 (ANR, 2026-11-23): «Ξεχωριστό WOD για άτομα» searches every member
 * of the box. Results come in two sections, those who booked the class first
 * («Έκλεισαν θέση»), then everyone else («Άλλα μέλη»); without a search only
 * the booked people show, as before. Pure: the dialog feeds it the class's
 * candidates and the directory's answer for the typed text.
 */
export function variationSections(
  booked: readonly VariationCandidate[],
  found: readonly { id: string; nickname: string; client?: boolean }[],
  query: string,
): { booked: VariationPerson[]; others: VariationPerson[] } {
  const needle = normalizeName(query);
  const bookedIds = new Set(booked.map((candidate) => candidate.userId));
  const bookedPeople = booked
    .filter((candidate) => !needle || normalizeName(candidate.nickname).includes(needle))
    .map((candidate) => ({ ...candidate, booked: true }));
  if (!needle) return { booked: bookedPeople, others: [] };
  const seen = new Set<string>();
  const others = found
    .filter((person) => person.client !== false && !bookedIds.has(person.id))
    .filter((person) => (seen.has(person.id) ? false : (seen.add(person.id), true)))
    .map((person) => ({ userId: person.id, nickname: person.nickname || person.id, hasVersion: false, booked: false }))
    .sort((a, b) => a.nickname.localeCompare(b.nickname));
  return { booked: bookedPeople, others };
}

function normalizeName(value: string) {
  return value
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLocaleLowerCase()
    .trim();
}

type ClassLike = {
  master_workout_id?: string | null;
  workout?: { id: string } | null;
  workouts?: readonly { id: string }[];
  live_workout_id?: string | null;
  bookings?: readonly (BookingLike & { chosen_workout_id?: string | null })[];
};

/** ADR-746: the class's WOD ids in order, tolerating payloads from before the list. */
export function classWorkoutIds(slot: ClassLike): string[] {
  const ids = (slot.workouts ?? []).map((workout) => workout.id);
  const first = slot.master_workout_id ?? slot.workout?.id ?? null;
  return [...new Set([...(first ? [first] : []), ...ids])];
}

/**
 * ADR-785 (3A): the class WOD a person's variant starts from: the WOD they
 * picked, else the coach's «Τώρα», else the first. Null when the class has
 * none. Matches the API's default when no source is sent.
 */
export function memberClassWorkoutId(slot: ClassLike, userId: string | null): string | null {
  const ids = classWorkoutIds(slot);
  const booking = userId
    ? slot.bookings?.find(
        (entry) =>
          entry.user_id === userId && !entry.guest_name && (entry.status === "approved" || entry.status === "pending"),
      )
    : undefined;
  const chosen = booking?.chosen_workout_id;
  if (chosen && ids.includes(chosen)) return chosen;
  const live = slot.live_workout_id;
  if (live && ids.includes(live)) return live;
  return ids[0] ?? null;
}
