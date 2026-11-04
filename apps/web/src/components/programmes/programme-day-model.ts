import type { ProgrammeBehindDay, ProgrammeBuyerDay, ProgrammeBuyerDayWorkout, ProgrammeDayStatus } from "@/api/programme-days";

/**
 * «Η μέρα μου» in a bought programme (board 3κ/3μ A, ADR-540): the progress,
 * the day left behind, the week's strip and the day in focus. Pure, and
 * tolerant of a payload with fields missing (e2e stubs answer `{}`).
 */
export const DAY_STATUSES: readonly ProgrammeDayStatus[] = ["done", "skipped", "behind", "today", "upcoming", "rest"];

export type DaysView = {
  days: ProgrammeBuyerDay[];
  weeks: number;
  progress: { done: number; total: number; skipped: number; behind: number; remaining: number };
  behind: NonNullable<ProgrammeBehindDay> | null;
  startsOn: string | null;
  today: string | null;
};

const count = (value: unknown) => (typeof value === "number" && Number.isFinite(value) && value >= 0 ? Math.floor(value) : 0);
const isoDate = (value: unknown) => (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null);

function readWorkout(value: unknown): ProgrammeBuyerDayWorkout | null {
  if (!value || typeof value !== "object") return null;
  const row = value as Record<string, unknown>;
  if (typeof row.workout_id !== "string") return null;
  return {
    workout_id: row.workout_id,
    assigned_workout_id: typeof row.assigned_workout_id === "string" ? row.assigned_workout_id : null,
    done: row.done === true,
    title: typeof row.title === "string" && row.title.trim() ? row.title : null,
    summary: typeof row.summary === "string" && row.summary.trim() ? row.summary : null,
  };
}

function readDay(value: unknown): ProgrammeBuyerDay | null {
  if (!value || typeof value !== "object") return null;
  const row = value as Record<string, unknown>;
  if (typeof row.day !== "number" || !Number.isInteger(row.day) || row.day < 0) return null;
  const workouts = Array.isArray(row.workouts) ? row.workouts.map(readWorkout).filter((entry): entry is ProgrammeBuyerDayWorkout => entry !== null) : [];
  const status = (DAY_STATUSES as readonly unknown[]).includes(row.status) ? (row.status as ProgrammeDayStatus) : workouts.length ? "upcoming" : "rest";
  return {
    day: row.day,
    week: Math.floor(row.day / 7) + 1,
    weekday: row.day % 7,
    date: isoDate(row.date) ?? "",
    status,
    workouts,
  };
}

function readBehind(value: unknown): NonNullable<ProgrammeBehindDay> | null {
  if (!value || typeof value !== "object") return null;
  const row = value as Record<string, unknown>;
  if (typeof row.day !== "number" || !Number.isInteger(row.day) || row.day < 0) return null;
  return {
    day: row.day,
    week: Math.floor(row.day / 7) + 1,
    weekday: row.day % 7,
    date: isoDate(row.date) ?? "",
    can_do_today: row.can_do_today === true,
    can_skip: row.can_skip !== false,
  };
}

export function readDays(data: unknown): DaysView {
  const payload = data && typeof data === "object" ? (data as Record<string, unknown>) : {};
  const days = (Array.isArray(payload.days) ? payload.days : [])
    .map(readDay)
    .filter((day): day is ProgrammeBuyerDay => day !== null)
    .sort((a, b) => a.day - b.day);
  const lastWeek = days.reduce((max, day) => Math.max(max, day.week), 0);
  const weeks = Math.max(count(payload.weeks), lastWeek);
  const progress = payload.progress && typeof payload.progress === "object" ? (payload.progress as Record<string, unknown>) : {};
  const trainingDays = days.filter((day) => day.status !== "rest").length;
  return {
    days,
    weeks,
    progress: {
      done: count(progress.done),
      total: count(progress.total) || trainingDays,
      skipped: count(progress.skipped),
      behind: count(progress.behind),
      remaining: count(progress.remaining),
    },
    behind: readBehind(payload.behind),
    startsOn: isoDate(payload.starts_on),
    today: isoDate(payload.today),
  };
}

/** Share of training days done, 0–100. */
export function progressPercent(progress: { done: number; total: number }) {
  if (progress.total <= 0) return 0;
  return Math.min(100, Math.max(0, Math.round((progress.done / progress.total) * 100)));
}

/** The week to open on: today's, else the next day to train, else the last one. */
export function focusWeek(view: DaysView): number {
  const today = view.days.find((day) => day.status === "today");
  if (today) return today.week;
  if (view.today) {
    const dated = view.days.find((day) => day.date && day.date >= view.today!);
    if (dated) return dated.week;
  }
  const next = view.days.find((day) => day.status === "upcoming" || day.status === "behind");
  if (next) return next.week;
  return Math.max(1, view.weeks);
}

/** The seven days of a week by weekday, a missing day shown as rest. */
export function weekDays(view: DaysView, week: number): ProgrammeBuyerDay[] {
  const byDay = new Map(view.days.filter((day) => day.week === week).map((day) => [day.weekday, day]));
  return Array.from({ length: 7 }, (_, weekday) => byDay.get(weekday) ?? { day: (week - 1) * 7 + weekday, week, weekday, date: "", status: "rest" as const, workouts: [] });
}

/** The day the card shows first: today, else the next to train, else the first left behind, else the week's first. */
export function focusDay(days: ProgrammeBuyerDay[]): number | null {
  const pick =
    days.find((day) => day.status === "today") ??
    days.find((day) => day.status === "upcoming") ??
    days.find((day) => day.status === "behind") ??
    days.find((day) => day.status !== "rest") ??
    days[0];
  return pick ? pick.day : null;
}

/**
 * Where «Ξεκίνα» (or «Δες την καταγραφή» on a done day) goes: the buyer's
 * assigned workout in Box › Προπονήσεις, the first one not yet done.
 */
export function dayWorkoutHref(day: ProgrammeBuyerDay): string | null {
  const assigned = day.workouts.filter((workout) => workout.assigned_workout_id);
  const pick = day.status === "done" ? assigned[0] : (assigned.find((workout) => !workout.done) ?? assigned[0]);
  return pick ? `/box/workouts?open_assignment=${encodeURIComponent(pick.assigned_workout_id!)}` : null;
}

/** A day the buyer can start now: today's, or one left behind. */
export function canStart(day: ProgrammeBuyerDay) {
  return (day.status === "today" || day.status === "behind") && dayWorkoutHref(day) !== null;
}
