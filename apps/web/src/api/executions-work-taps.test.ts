import { describe, expect, it } from "vitest";

import { addWorkTap, MAX_WORK_TAPS_PER_SECTION, planKpiCounters } from "@/api/executions";

describe("work taps (ADR-549)", () => {
  it("adds taps in order, once per time, keeping the other counters", () => {
    let counters = addWorkTap({ pauses: 2 }, "s1", 20_400.6);
    counters = addWorkTap(counters, "s1", 10_000);
    counters = addWorkTap(counters, "s1", 10_000);
    expect(counters).toEqual({ pauses: 2, activity: { s1: [10_000, 20_401] } });
  });

  it("stops at the server's limit per section", () => {
    let counters = {};
    for (let i = 0; i <= MAX_WORK_TAPS_PER_SECTION; i++) counters = addWorkTap(counters, "s1", i);
    expect(planKpiCounters({}).activity).toBeUndefined();
    expect((counters as { activity: Record<string, number[]> }).activity.s1).toHaveLength(MAX_WORK_TAPS_PER_SECTION);
  });

  it("turns a plan run's taps by section into counters", () => {
    expect(planKpiCounters({ a: [3_000, 1_000], b: [] })).toEqual({ activity: { a: [1_000, 3_000] } });
  });
});
