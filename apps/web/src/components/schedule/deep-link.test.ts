import { describe, expect, it } from "vitest";

import { scheduleDeepLink } from "./deep-link";

describe("scheduleDeepLink", () => {
  it("reads the class and its day", () => {
    expect(scheduleDeepLink({ open_slot: "s1", open_day: "2026-11-04" })).toEqual({ slotId: "s1", day: "2026-11-04" });
  });

  it("ignores a malformed day and a day without a class", () => {
    expect(scheduleDeepLink({ open_slot: "s1", open_day: "4/11/2026" })).toEqual({ slotId: "s1", day: null });
    expect(scheduleDeepLink({ open_day: "2026-11-04" })).toEqual({ slotId: null, day: null });
  });

  it("takes the first of repeated values", () => {
    expect(scheduleDeepLink({ open_slot: ["s1", "s2"], open_day: ["2026-11-04"] })).toEqual({ slotId: "s1", day: "2026-11-04" });
  });
});
