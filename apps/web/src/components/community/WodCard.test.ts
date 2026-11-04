import { describe, expect, it } from "vitest";

import { wodScheduleHref } from "./WodCard";

const classes = [
  { id: "c-1830", scheduled_at: "2026-11-04T16:30:00Z" },
  { id: "c-1000", scheduled_at: "2026-11-04T08:00:00Z" },
  { id: "c-2030", scheduled_at: "2026-11-04T18:30:00Z" },
];

describe("wodScheduleHref", () => {
  it("opens the next class of the day in the box schedule", () => {
    expect(wodScheduleHref("box1", classes, new Date("2026-11-04T09:00:00Z"))).toBe("/org/box1/box/schedule?open_slot=c-1830");
  });

  it("opens the last class once every class has started", () => {
    expect(wodScheduleHref("box1", classes, new Date("2026-11-04T20:00:00Z"))).toBe("/org/box1/box/schedule?open_slot=c-2030");
  });

  it("opens the schedule alone when no class carries the WOD", () => {
    expect(wodScheduleHref(null, [], new Date("2026-11-04T09:00:00Z"))).toBe("/box/schedule");
  });
});
