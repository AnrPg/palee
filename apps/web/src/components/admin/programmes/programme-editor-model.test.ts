import { describe, expect, it } from "vitest";

import type { ProgrammeDay, StaffProgramme } from "@/api/programmes";
import type { WorkoutRecord } from "@/api/workouts";

import {
  addEquipment,
  addableEquipment,
  changesOf,
  copyWeek,
  copyWeekToNext,
  dayRange,
  deleteWeek,
  draftOf,
  EQUIPMENT_KEYS,
  filterLibrary,
  libraryFamilies,
  libraryOf,
  liveReadiness,
  MAX_ADDED_EQUIPMENT,
  moveCursor,
  moveWeek,
  pasteDay,
  placeWorkout,
  readinessTarget,
  recentWorkouts,
  removeEquipment,
  restDays,
  setDay,
  shownEquipment,
  trainingDays,
  workoutsOn,
} from "./programme-editor-model";

const d = (day: number, workout_id: string): ProgrammeDay => ({ day, workout_id });

function programme(overrides: Partial<StaffProgramme> = {}): StaffProgramme {
  return {
    id: "p-1",
    title: "Strength in 6 weeks",
    summary: null,
    level: "intermediate",
    goal: "strength",
    status: "draft",
    draft_weeks: 2,
    draft_days: [d(0, "w-a")],
    currency: "EUR",
    listing: "box",
    preview_days: 3,
    price_cents: 0,
    refund_policy: "before_start",
    readiness: [],
    equipment: [],
    equipment_removed: [],
    ...overrides,
  } as StaffProgramme;
}

describe("draft and changes", () => {
  it("sends nothing when the draft matches the saved programme", () => {
    const saved = programme();
    expect(changesOf(saved, draftOf(saved))).toBeNull();
  });

  it("sends only what changed, with the days whenever the weeks change", () => {
    const saved = programme();
    const draft = { ...draftOf(saved), weeks: 3, summary: "  Get strong  ", equipment: ["rower" as const] };
    expect(changesOf(saved, draft)).toEqual({ draft_weeks: 3, draft_days: [d(0, "w-a")], summary: "Get strong", equipment: ["rower"] });
  });

  it("never sends a title shorter than two characters", () => {
    const saved = programme();
    expect(changesOf(saved, { ...draftOf(saved), title: " a " })).toBeNull();
  });

  it("sends the removed equipment keys", () => {
    const saved = programme();
    expect(changesOf(saved, { ...draftOf(saved), equipmentRemoved: ["barbell"] })).toEqual({ equipment_removed: ["barbell"] });
  });
});

describe("day operations", () => {
  const days = [d(0, "w-a"), d(2, "w-b"), d(2, "w-c"), d(8, "w-a")];

  it("reads a day's WODs and a week's training days", () => {
    expect(workoutsOn(days, 2)).toEqual(["w-b", "w-c"]);
    expect(trainingDays(days, 0)).toBe(2);
    expect(trainingDays(days, 1)).toBe(1);
    expect(trainingDays(days, 2)).toBe(0);
  });

  it("sets a day, dropping duplicates and keeping at most four WODs", () => {
    expect(workoutsOn(setDay(days, 0, ["w-x", "w-x", "w-y"]), 0)).toEqual(["w-x", "w-y"]);
    expect(workoutsOn(setDay([], 3, ["a", "b", "c", "d", "e"]), 3)).toHaveLength(4);
  });

  it("makes days rest days", () => {
    expect(restDays(days, [2, 8])).toEqual([d(0, "w-a")]);
  });

  it("places a WOD on several days, skipping days that have it and counting full ones", () => {
    const full = [d(5, "a"), d(5, "b"), d(5, "c"), d(5, "d")];
    const result = placeWorkout([...days, ...full], [0, 1, 5], "w-a");
    expect(result.placed).toBe(1);
    expect(result.full).toBe(1);
    expect(workoutsOn(result.days, 1)).toEqual(["w-a"]);
  });

  it("pastes a copied day over the targets, and an empty copy makes them rest", () => {
    expect(workoutsOn(pasteDay(days, ["w-z"], [2, 3]), 2)).toEqual(["w-z"]);
    expect(workoutsOn(pasteDay(days, [], [2]), 2)).toEqual([]);
  });
});

describe("week operations (ADR-544)", () => {
  const week0 = [d(0, "w-a"), d(1, "w-b"), d(3, "w-c")];

  it("copies a week filling only the empty days of the target week", () => {
    const planned = [...week0, d(8, "w-x")];
    const result = copyWeek(planned, 0, [1]);
    expect(result.filled).toBe(2);
    expect(workoutsOn(result.days, 7)).toEqual(["w-a"]);
    expect(workoutsOn(result.days, 8)).toEqual(["w-x"]);
    expect(workoutsOn(result.days, 10)).toEqual(["w-c"]);
  });

  it("copies to several weeks and ignores the week itself", () => {
    const result = copyWeek(week0, 0, [0, 1, 2]);
    expect(result.filled).toBe(6);
  });

  it("copies to the next week, adding a week after the last one", () => {
    const result = copyWeekToNext(week0, 1, 0);
    expect(result.weeks).toBe(2);
    expect(result.week).toBe(1);
    expect(result.filled).toBe(3);
  });

  it("deletes a week and moves the later weeks back", () => {
    const result = deleteWeek([d(0, "a"), d(8, "b"), d(15, "c")], 3, 1);
    expect(result).toEqual({ weeks: 2, days: [d(0, "a"), d(8, "c")] });
    expect(deleteWeek([d(0, "a")], 1, 0)).toEqual({ weeks: 1, days: [d(0, "a")] });
  });

  it("moves a week to another position", () => {
    expect(moveWeek([d(0, "a"), d(8, "b"), d(16, "c")], 3, 2, 0)).toEqual([d(2, "c"), d(7, "a"), d(15, "b")]);
    expect(moveWeek([d(0, "a")], 1, 0, 3)).toEqual([d(0, "a")]);
  });
});

describe("grid selection", () => {
  it("selects a range in reading order either way", () => {
    expect(dayRange(9, 6)).toEqual([6, 7, 8, 9]);
  });

  it("moves the cursor with arrows, Home and End, inside the grid", () => {
    expect(moveCursor(0, "ArrowLeft", 2)).toBe(0);
    expect(moveCursor(6, "ArrowRight", 2)).toBe(7);
    expect(moveCursor(3, "ArrowDown", 2)).toBe(10);
    expect(moveCursor(10, "ArrowDown", 2)).toBe(10);
    expect(moveCursor(10, "Home", 2)).toBe(7);
    expect(moveCursor(10, "End", 2)).toBe(13);
  });
});

describe("readiness", () => {
  it("lists the missing title, days and summary", () => {
    expect(liveReadiness({ title: " ", summary: "", weeks: 2, days: [] }).map((item) => item.key)).toEqual(["title", "days", "summary"]);
  });

  it("names the empty weeks once some day has a WOD, and nothing when ready", () => {
    expect(liveReadiness({ title: "T", summary: "", weeks: 3, days: [d(7, "a")] })).toEqual([
      { key: "empty_weeks", blocking: false, weeks: [1, 3] },
      { key: "summary", blocking: false, weeks: [] },
    ]);
    expect(liveReadiness({ title: "T", summary: "S", weeks: 1, days: [d(0, "a")] })).toEqual([]);
  });

  it("takes the coach to the place to fix each item", () => {
    expect(readinessTarget({ key: "empty_weeks", blocking: false, weeks: [5, 6] })).toEqual({ tab: "weeks", week: 4 });
    expect(readinessTarget({ key: "summary", blocking: false, weeks: [] })).toEqual({ tab: "details", field: "summary" });
    expect(readinessTarget({ key: "price", blocking: true, weeks: [] })).toBeNull();
  });
});

describe("equipment (ADR-542)", () => {
  it("shows the added keys first, then the derived ones not removed", () => {
    expect(shownEquipment(["barbell", "rower"], ["rings"], ["rower"])).toEqual(["rings", "barbell"]);
  });

  it("removes an added key outright and remembers a derived one", () => {
    expect(removeEquipment(["barbell"], ["rings"], [], "rings")).toEqual({ equipment: [], equipmentRemoved: [] });
    expect(removeEquipment(["barbell"], [], [], "barbell")).toEqual({ equipment: [], equipmentRemoved: ["barbell"] });
  });

  it("brings a removed key back, adds others up to the limit", () => {
    expect(addEquipment(["barbell"], [], ["barbell"], "barbell")).toEqual({ equipment: [], equipmentRemoved: [] });
    expect(addEquipment([], [], [], "rower")).toEqual({ equipment: ["rower"], equipmentRemoved: [] });
    const many = EQUIPMENT_KEYS.slice(1, 1 + MAX_ADDED_EQUIPMENT);
    expect(addEquipment([], [...many], [], "foam_roller").equipment).toHaveLength(MAX_ADDED_EQUIPMENT);
  });

  it("offers every key not shown, and only removed ones once the limit is reached", () => {
    expect(addableEquipment(["barbell"], ["rings"], [])).not.toContain("barbell");
    expect(addableEquipment(["barbell"], ["rings"], [])).toContain("rower");
    const many = EQUIPMENT_KEYS.slice(2, 2 + MAX_ADDED_EQUIPMENT);
    expect(addableEquipment(["barbell"], [...many], ["barbell"])).toEqual(["barbell"]);
  });
});

describe("WOD library", () => {
  const workout = (id: string, title: string, type: string, status = "published", extra: Record<string, unknown> = {}) =>
    ({ id, title, type, status, available_scale_levels: [], sections: [], ...extra }) as WorkoutRecord;
  const library = libraryOf([
    workout("w-1", "Back squat 5×5", "strength", "published", { estimated_duration_seconds: 3000 }),
    workout("w-2", "Fran", "crossfit"),
    workout("w-3", "Draft", "running", "draft"),
  ]);

  it("keeps the published WODs with their family and stated length", () => {
    expect(library.map((item) => [item.id, item.family, item.minutes])).toEqual([
      ["w-1", "strength", 50],
      ["w-2", "functional", null],
    ]);
  });

  it("filters by text and family, and lists the families present in catalogue order", () => {
    expect(filterLibrary(library, "fran", null).map((item) => item.id)).toEqual(["w-2"]);
    expect(filterLibrary(library, "", "strength").map((item) => item.id)).toEqual(["w-1"]);
    expect(libraryFamilies(library)).toEqual(["functional", "strength"]);
  });

  it("lists the programme's WODs as recent, the latest day first", () => {
    expect(recentWorkouts([d(0, "a"), d(3, "b"), d(9, "a")], 5)).toEqual(["a", "b"]);
  });
});
