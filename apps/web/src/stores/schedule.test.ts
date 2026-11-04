import { beforeEach, describe, expect, it } from "vitest";

import { useScheduleStore } from "./schedule";

describe("useScheduleStore", () => {
  beforeEach(() => useScheduleStore.setState({ days: 30, startDate: "2026-10-01" }));

  it("openDay switches to the day view of that date", () => {
    useScheduleStore.getState().openDay("2026-10-14");

    expect(useScheduleStore.getState()).toMatchObject({ days: 1, startDate: "2026-10-14" });
  });

  it("the day view steps one day at a time", () => {
    useScheduleStore.getState().openDay("2026-10-31");
    useScheduleStore.getState().shiftWindow(1);
    expect(useScheduleStore.getState().startDate).toBe("2026-11-01");

    useScheduleStore.getState().shiftWindow(-1);
    useScheduleStore.getState().shiftWindow(-1);
    expect(useScheduleStore.getState().startDate).toBe("2026-10-30");
  });

  it("focusDay moves to a linked class's day, keeps the view length and drops the type filter", () => {
    useScheduleStore.setState({ days: 7, startDate: "2026-01-05", classTypeIds: ["type-1"] });
    useScheduleStore.getState().focusDay("2026-11-04");
    expect(useScheduleStore.getState()).toMatchObject({ days: 7, startDate: "2026-11-04", classTypeIds: [] });
  });
});
