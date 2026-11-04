import { describe, expect, it } from "vitest";

import {
  addDays,
  addWorkout,
  columnsFor,
  emptyWeeks,
  needsStartRequest,
  programmeDayOf,
  programmeProgress,
  removeWorkout,
  sameDays,
  trimToWeeks,
  weekRows,
} from "./programme-grid";

const A = "00000000-0000-0000-0000-00000000000a";
const B = "00000000-0000-0000-0000-00000000000b";

describe("programme grid", () => {
  it("lays days out as weeks of numbered days", () => {
    const rows = weekRows(2, [{ day: 0, workout_id: A }, { day: 9, workout_id: B }], 5);
    expect(rows).toHaveLength(2);
    expect(rows[0].cells[0]).toEqual({ day: 0, workoutIds: [A] });
    expect(rows[1].cells[2]).toEqual({ day: 9, workoutIds: [B] });
    expect(rows[1].cells).toHaveLength(5);
  });

  it("shows at least five days, more when a later day is used", () => {
    expect(columnsFor([])).toBe(5);
    expect(columnsFor([{ day: 13, workout_id: A }])).toBe(7);
    expect(columnsFor([], 6)).toBe(6);
  });

  it("adds at most four different WODs a day and removes one", () => {
    let days = addWorkout([], 3, A);
    days = addWorkout(days, 3, A);
    expect(days).toEqual([{ day: 3, workout_id: A }]);
    for (const n of [1, 2, 3, 4]) days = addWorkout(days, 3, `w${n}`);
    expect(days.filter((row) => row.day === 3)).toHaveLength(4);
    expect(removeWorkout(days, 3, A).some((row) => row.workout_id === A)).toBe(false);
  });

  it("drops days of removed weeks and finds empty weeks", () => {
    const days = [{ day: 0, workout_id: A }, { day: 15, workout_id: B }];
    expect(trimToWeeks(days, 2)).toEqual([{ day: 0, workout_id: A }]);
    expect(emptyWeeks(3, [{ day: 0, workout_id: A }])).toEqual([2, 3]);
  });

  it("compares drafts regardless of order", () => {
    expect(sameDays([{ day: 1, workout_id: B }, { day: 0, workout_id: A }], [{ day: 0, workout_id: A }, { day: 1, workout_id: B }])).toBe(true);
    expect(sameDays([{ day: 1, workout_id: B }], [])).toBe(false);
  });
});

describe("buying a programme", () => {
  it("asks to start only when the start falls inside the withdrawal days", () => {
    const today = "2026-11-03";
    expect(needsStartRequest(today, today, 14)).toBe(true);
    expect(needsStartRequest(addDays(today, 13), today, 14)).toBe(true);
    expect(needsStartRequest(addDays(today, 14), today, 14)).toBe(false);
    expect(needsStartRequest(today, today, null)).toBe(false);
  });

  it("names the week and day of a date and the progress", () => {
    expect(programmeDayOf("2026-11-02", "2026-11-11")).toEqual({ week: 2, day: 3 });
    expect(programmeDayOf("2026-11-02", "2026-11-01")).toBeNull();
    expect(programmeProgress("2026-11-01", "2026-11-30", "2026-11-08")).toEqual({ done: 8, total: 30 });
    expect(programmeProgress("2026-11-10", "2026-11-30", "2026-11-08")).toEqual({ done: 0, total: 21 });
  });
});
