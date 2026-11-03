import type { ProgrammeDay } from "@/api/programmes";

/**
 * The builder's weeks grid (mockup W8 s1 A): one row per week, one cell per
 * day of the week. Day 0 is the buyer's start date, so cells are numbered
 * days («Ημ. 1»), never weekdays: the buyer chooses the start.
 */
export const DAYS_PER_WEEK = 7;
export const MAX_WODS_PER_DAY = 4;
export const MAX_WEEKS = 52;

export type GridCell = { day: number; workoutIds: string[] };
export type GridWeek = { week: number; cells: GridCell[] };

export function dayIndex(week: number, slot: number) {
  return week * DAYS_PER_WEEK + slot;
}

/** The weeks of a draft, each with `columns` cells (the days shown per week). */
export function weekRows(weeks: number, days: ProgrammeDay[], columns: number): GridWeek[] {
  const byDay = new Map<number, string[]>();
  for (const row of days) byDay.set(row.day, [...(byDay.get(row.day) ?? []), row.workout_id]);
  return Array.from({ length: Math.max(1, weeks) }, (_, week) => ({
    week,
    cells: Array.from({ length: columns }, (_, slot) => {
      const day = dayIndex(week, slot);
      return { day, workoutIds: byDay.get(day) ?? [] };
    }),
  }));
}

/** The days shown per week: at least 5, more when a later day already has a WOD. */
export function columnsFor(days: ProgrammeDay[], chosen?: number | null) {
  const used = days.reduce((max, row) => Math.max(max, (row.day % DAYS_PER_WEEK) + 1), 0);
  return Math.min(DAYS_PER_WEEK, Math.max(chosen ?? 5, used, 1));
}

export function addWorkout(days: ProgrammeDay[], day: number, workoutId: string): ProgrammeDay[] {
  const same = days.filter((row) => row.day === day);
  if (same.length >= MAX_WODS_PER_DAY || same.some((row) => row.workout_id === workoutId)) return days;
  return sortDays([...days, { day, workout_id: workoutId }]);
}

export function removeWorkout(days: ProgrammeDay[], day: number, workoutId: string): ProgrammeDay[] {
  return days.filter((row) => !(row.day === day && row.workout_id === workoutId));
}

/** Drops the days of weeks that no longer exist. */
export function trimToWeeks(days: ProgrammeDay[], weeks: number): ProgrammeDay[] {
  return days.filter((row) => row.day < weeks * DAYS_PER_WEEK);
}

/** A week with no WOD at all (publishing warns about it inside the dialog). */
export function emptyWeeks(weeks: number, days: ProgrammeDay[]) {
  const used = new Set(days.map((row) => Math.floor(row.day / DAYS_PER_WEEK)));
  return Array.from({ length: weeks }, (_, week) => week).filter((week) => !used.has(week)).map((week) => week + 1);
}

export function sortDays(days: ProgrammeDay[]) {
  return [...days].sort((a, b) => a.day - b.day || a.workout_id.localeCompare(b.workout_id));
}

export function sameDays(a: ProgrammeDay[], b: ProgrammeDay[]) {
  const left = sortDays(a);
  const right = sortDays(b);
  return left.length === right.length && left.every((row, index) => row.day === right[index].day && row.workout_id === right[index].workout_id);
}

// ── Buying ────────────────────────────────────────────────────────────────

/** ISO date plus `days`. */
export function addDays(iso: string, days: number) {
  const [year, month, day] = iso.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

export function daysBetween(from: string, to: string) {
  const [a, b] = [from, to].map((iso) => {
    const [year, month, day] = iso.split("-").map(Number);
    return Date.UTC(year, month - 1, day);
  });
  return Math.round((b - a) / 86_400_000);
}

/**
 * Whether the buyer must ask for the programme to start (mockup W8 s5 A):
 * only where a right of withdrawal exists and the start date falls inside
 * its days. The box is never ticked in advance (Directive 2011/83/EU 16(m)).
 */
export function needsStartRequest(startsOn: string, today: string, withdrawalDays: number | null | undefined) {
  if (!withdrawalDays) return false;
  return daysBetween(today, startsOn) < withdrawalDays;
}

/** «Εβδ. 2 · Ημέρα 3»: where a date falls in a purchase that starts on `startsOn` (1-based). */
export function programmeDayOf(startsOn: string, date: string) {
  const offset = daysBetween(startsOn, date);
  if (offset < 0) return null;
  return { week: Math.floor(offset / DAYS_PER_WEEK) + 1, day: (offset % DAYS_PER_WEEK) + 1 };
}

/** Days done out of all the programme's days (calendar days, start to end). */
export function programmeProgress(startsOn: string, endsOn: string, today: string) {
  const total = daysBetween(startsOn, endsOn) + 1;
  const done = Math.min(total, Math.max(0, daysBetween(startsOn, today) + 1));
  return { done, total };
}


/** An ISO day as a Date at UTC midnight, for formatting with `timeZone: "UTC"`. */
export function utcDay(iso: string) {
  const [year, month, day] = iso.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day));
}
