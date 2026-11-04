import { describe, expect, it } from "vitest";

import { canOpenBoxSchedule, msUntilNextWodClass, wodScheduleHref } from "./WodCard";

const classes = [
  { id: "c-1830", scheduled_at: "2026-11-04T16:30:00Z" },
  { id: "c-1000", scheduled_at: "2026-11-04T08:00:00Z" },
  { id: "c-2030", scheduled_at: "2026-11-04T18:30:00Z" },
];

describe("wodScheduleHref", () => {
  it("opens the next class of the day, on its day, in the box schedule", () => {
    expect(wodScheduleHref("box1", classes, "2026-11-04", new Date("2026-11-04T09:00:00Z"))).toBe(
      "/org/box1/box/schedule?open_slot=c-1830&open_day=2026-11-04",
    );
  });

  it("opens the last class once every class has started", () => {
    expect(wodScheduleHref("box1", classes, "2026-11-04", new Date("2026-11-04T20:00:00Z"))).toBe(
      "/org/box1/box/schedule?open_slot=c-2030&open_day=2026-11-04",
    );
  });

  it("opens the schedule alone when no class carries the WOD", () => {
    expect(wodScheduleHref(null, [], "2026-11-04", new Date("2026-11-04T09:00:00Z"))).toBe("/box/schedule");
  });

  it("orders by instant, not by text, when offsets differ", () => {
    const mixed = [
      { id: "second", scheduled_at: "2026-11-04T08:00:00Z" },
      { id: "first", scheduled_at: "2026-11-04T09:00:00+02:00" },
    ];
    expect(wodScheduleHref(null, mixed, "2026-11-04", new Date("2026-11-04T06:00:00Z"))).toBe(
      "/box/schedule?open_slot=first&open_day=2026-11-04",
    );
  });
});

describe("msUntilNextWodClass", () => {
  it("counts to just after the next class start", () => {
    expect(msUntilNextWodClass(classes, new Date("2026-11-04T16:29:00Z"))).toBe(60_001);
  });

  it("is null once every class has started", () => {
    expect(msUntilNextWodClass(classes, new Date("2026-11-04T19:00:00Z"))).toBeNull();
  });
});

describe("canOpenBoxSchedule", () => {
  it("lets members and staff open the schedule, nobody else", () => {
    expect(canOpenBoxSchedule("member")).toBe(true);
    expect(canOpenBoxSchedule("admin")).toBe(true);
    expect(canOpenBoxSchedule("athlete")).toBe(false);
    expect(canOpenBoxSchedule(null)).toBe(false);
  });
});
