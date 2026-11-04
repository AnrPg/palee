import { describe, expect, it } from "vitest";

import { canStart, dayWorkoutHref, focusDay, focusWeek, progressPercent, readDays, weekDays } from "./programme-day-model";

const workout = (id: string, done = false, assigned: string | null = `a-${id}`) => ({ workout_id: id, assigned_workout_id: assigned, done, title: `WOD ${id}`, summary: null });

const payload = {
  purchase_id: "p1",
  starts_on: "2026-10-26",
  today: "2026-11-05",
  weeks: 2,
  progress: { done: 1, total: 6, skipped: 0, behind: 1, remaining: 5 },
  behind: { day: 8, week: 2, weekday: 1, date: "2026-11-03", can_do_today: true, can_skip: true },
  days: [
    { day: 0, week: 1, weekday: 0, date: "2026-10-26", status: "done", workouts: [workout("w0", true)] },
    { day: 2, week: 1, weekday: 2, date: "2026-10-28", status: "skipped", workouts: [workout("w2")] },
    { day: 3, week: 1, weekday: 3, date: "2026-10-29", status: "rest", workouts: [] },
    { day: 8, week: 2, weekday: 1, date: "2026-11-03", status: "behind", workouts: [workout("w8")] },
    { day: 10, week: 2, weekday: 3, date: "2026-11-05", status: "today", workouts: [workout("w10a", true), workout("w10b")] },
    { day: 12, week: 2, weekday: 5, date: "2026-11-07", status: "upcoming", workouts: [workout("w12", false, null)] },
  ],
};

describe("programme day model (ADR-540)", () => {
  it("reads the days, the progress and the day left behind", () => {
    const view = readDays(payload);
    expect(view.days).toHaveLength(6);
    expect(view.weeks).toBe(2);
    expect(view.progress).toMatchObject({ done: 1, total: 6 });
    expect(view.behind).toMatchObject({ day: 8, can_do_today: true, can_skip: true });
    expect(progressPercent(view.progress)).toBe(17);
  });

  it("tolerates a stub that answers {} or rows of the wrong shape", () => {
    const view = readDays({});
    expect(view).toMatchObject({ days: [], weeks: 0, behind: null, progress: { done: 0, total: 0 } });
    expect(progressPercent(view.progress)).toBe(0);
    expect(focusWeek(view)).toBe(1);
    expect(readDays(null).days).toEqual([]);
    const odd = readDays({ days: [null, { day: "1" }, { day: 4, status: "weird", workouts: [{ title: "no id" }] }], behind: { day: -1 } });
    expect(odd.days).toEqual([{ day: 4, week: 1, weekday: 4, date: "", status: "rest", workouts: [] }]);
    expect(odd.behind).toBeNull();
  });

  it("opens on today's week and focuses today", () => {
    const view = readDays(payload);
    expect(focusWeek(view)).toBe(2);
    const week = weekDays(view, 2);
    expect(week.map((day) => day.status)).toEqual(["rest", "behind", "rest", "today", "rest", "upcoming", "rest"]);
    expect(week.map((day) => day.day)).toEqual([7, 8, 9, 10, 11, 12, 13]);
    expect(focusDay(week)).toBe(10);
    expect(focusDay(weekDays(view, 1))).toBe(0);
  });

  it("starts the first assigned WOD not done yet, and only today or behind", () => {
    const view = readDays(payload);
    const today = view.days.find((day) => day.day === 10)!;
    expect(dayWorkoutHref(today)).toBe("/box/workouts?open_assignment=a-w10b");
    expect(canStart(today)).toBe(true);
    expect(canStart(view.days.find((day) => day.day === 8)!)).toBe(true);
    expect(canStart(view.days.find((day) => day.day === 12)!)).toBe(false);
    const done = view.days.find((day) => day.day === 0)!;
    expect(dayWorkoutHref(done)).toBe("/box/workouts?open_assignment=a-w0");
    expect(canStart(done)).toBe(false);
  });
});
