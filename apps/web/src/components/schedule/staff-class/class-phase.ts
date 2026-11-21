/**
 * Where a class stands for staff right now, which decides what its page puts
 * first and what the bar at the bottom offers (ANR's class page pick A,
 * 2026-11-21):
 *
 * - `upcoming`: more than {@link START_SOON_MINUTES} minutes before the start.
 *   The bar edits the class or its WOD.
 * - `soon`: the last {@link START_SOON_MINUTES} minutes before the start.
 * - `live`: from the start until the class ends.
 * - `ended`: after the end.
 *
 * Pure, so the page and its tests share one clock rule.
 */
export type ClassPhase = "upcoming" | "soon" | "live" | "ended";

/** From this long before the start, «Έναρξη τμήματος» takes the bar. */
export const START_SOON_MINUTES = 30;

/** The box's own check-in window when its rules are not readable (CheckInRules defaults). */
export const DEFAULT_CHECK_IN_BEFORE_MINUTES = 30;

const MINUTE = 60_000;

type Timed = { scheduled_at: string; duration_minutes: number };

export function classPhase(slot: Timed, now: number): ClassPhase {
  const start = Date.parse(slot.scheduled_at);
  const end = start + Math.max(0, slot.duration_minutes) * MINUTE;
  if (now >= end) return "ended";
  if (now >= start) return "live";
  if (now >= start - START_SOON_MINUTES * MINUTE) return "soon";
  return "upcoming";
}

/** Whole minutes until the start, never below zero (for «Σε 20′»). */
export function minutesUntilStart(slot: Timed, now: number) {
  return Math.max(0, Math.ceil((Date.parse(slot.scheduled_at) - now) / MINUTE));
}

/**
 * Staff mark «Ήρθε» from the moment the box's check-in window opens (its
 * «Ρυθμίσεις › Check-in» rule, `window_before_minutes`) and any time after,
 * so a forgotten check-in can still be recorded once the class is over.
 */
export function staffCheckInOpen(slot: Timed, now: number, windowBeforeMinutes?: number | null) {
  const before = windowBeforeMinutes ?? DEFAULT_CHECK_IN_BEFORE_MINUTES;
  return now >= Date.parse(slot.scheduled_at) - Math.max(0, before) * MINUTE;
}

/** The next moment the phase or the check-in window changes, for a timer; null when nothing changes any more. */
export function nextPhaseChange(slot: Timed, now: number, windowBeforeMinutes?: number | null) {
  const start = Date.parse(slot.scheduled_at);
  const before = windowBeforeMinutes ?? DEFAULT_CHECK_IN_BEFORE_MINUTES;
  const moments = [
    start - START_SOON_MINUTES * MINUTE,
    start - Math.max(0, before) * MINUTE,
    start,
    start + Math.max(0, slot.duration_minutes) * MINUTE,
  ].filter((moment) => moment > now);
  return moments.length ? Math.min(...moments) : null;
}
