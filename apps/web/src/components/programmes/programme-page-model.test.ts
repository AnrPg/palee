import { describe, expect, it } from "vitest";

import { coverUrl, knownEquipment, previewDays, programmeFacts, refundPolicy, weekOutline } from "./programme-page-model";

const programme = {
  weeks: 6,
  sessions_per_week: 4,
  minutes_per_session: 45,
  main_equipment: ["barbell", "dumbbell", "rower"],
  refund_policy: "before_start",
  preview: [
    { day: 0, week: 1, weekday: 0, title: "Back squat 5×5" },
    { day: 1, week: 1, weekday: 1, title: "Fran" },
  ],
  week_outline: [1, 2, 3, 4, 5, 6].map((week) => ({ week, sessions: 4 })),
};

describe("programme page model", () => {
  it("shows the minutes and the equipment only when the API knows them (ADR-542)", () => {
    expect(programmeFacts(programme)).toEqual({ weeks: 6, perWeek: 4, minutes: 45, equipment: ["barbell", "dumbbell"] });
    expect(programmeFacts({ ...programme, minutes_per_session: null, main_equipment: [] })).toMatchObject({ minutes: null, equipment: [] });
  });

  it("reads a malformed or empty payload as no facts", () => {
    expect(programmeFacts({})).toEqual({ weeks: null, perWeek: null, minutes: null, equipment: [] });
    expect(programmeFacts(null)).toEqual({ weeks: null, perWeek: null, minutes: null, equipment: [] });
    expect(programmeFacts({ weeks: "6", minutes_per_session: -5, main_equipment: "barbell" })).toEqual({ weeks: null, perWeek: null, minutes: null, equipment: [] });
    expect(knownEquipment(["barbell", "laser", 3, "barbell"])).toEqual(["barbell"]);
  });

  it("uses the cover photo when there is one, else the theme strip", () => {
    expect(coverUrl({ cover_url: "https://media.example/cover.webp" })).toBe("https://media.example/cover.webp");
    expect(coverUrl({ cover_url: null })).toBeNull();
    expect(coverUrl({ cover_url: "javascript:alert(1)" })).toBeNull();
    expect(coverUrl({})).toBeNull();
  });

  it("names a known refund rule only", () => {
    expect(refundPolicy(programme)).toBe("before_start");
    expect(refundPolicy({ refund_policy: "whatever" })).toBeNull();
  });

  it("groups the preview rows by day", () => {
    const days = previewDays({ preview: [{ day: 1, title: "B" }, { day: 1, title: "C" }, { day: 0, title: "A" }, { day: "x" }, null] });
    expect(days).toEqual([
      { day: 0, week: 1, dayOfWeek: 1, titles: ["A"] },
      { day: 1, week: 1, dayOfWeek: 2, titles: ["B", "C"] },
    ]);
  });

  it("opens the preview weeks one by one, one more week, then the rest together (2κ A)", () => {
    const outline = weekOutline(programme);
    expect(outline.map(({ from, to }) => [from, to])).toEqual([
      [1, 1],
      [2, 2],
      [3, 6],
    ]);
    expect(outline[0].open.map((day) => day.titles[0])).toEqual(["Back squat 5×5", "Fran"]);
    expect(outline[0].locked).toBe(2);
    expect(outline[1].locked).toBe(4);
    expect(outline[2].locked).toBe(16);
  });

  it("shows week 1 and the rest when nothing is free, and nothing for an empty payload", () => {
    expect(weekOutline({ weeks: 2, sessions_per_week: 3 }).map(({ from, to, locked }) => [from, to, locked])).toEqual([
      [1, 1, 3],
      [2, 2, 3],
    ]);
    expect(weekOutline({})).toEqual([]);
    expect(weekOutline({ weeks: 1, preview: "nope", week_outline: {} })).toEqual([{ from: 1, to: 1, open: [], locked: 0 }]);
  });
});
