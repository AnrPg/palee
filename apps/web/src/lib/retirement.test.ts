import { describe, expect, it } from "vitest";

import type { TimerSegment } from "@/api/executions";

import { stoppedEarlySections, timeSetSections } from "./retirement";

const segment = (over: Partial<TimerSegment>): TimerSegment =>
  ({
    segment_key: `segment:${over.section_id}`,
    section_id: "a",
    section_name: "A",
    kind: "countdown",
    phase: "work",
    duration_seconds: 600,
    exercises: [],
    ...over,
  }) as TimerSegment;

describe("ADR-549 time-set sections", () => {
  it("keeps countdowns and fixed windows, drops count-ups, open windows, rests and time scores", () => {
    const sections = timeSetSections([
      segment({ section_id: "amrap", section_name: "AMRAP" }),
      segment({ section_id: "ft", kind: "countup" }),
      segment({ section_id: "emom", kind: "interval_cycle", duration_seconds: 60, total_rounds: 10 }),
      segment({ section_id: "open", kind: "interval_cycle", duration_seconds: 60, total_rounds: null }),
      segment({
        section_id: "tabata",
        kind: "interval_cycle",
        duration_seconds: 20,
        total_rounds: 3,
        timer_config: { interval_pattern_seconds: [20, 10] },
      }),
      segment({ section_id: "rest", phase: "rest", duration_seconds: 120 }),
      segment({ section_id: "timed", score_config: { type: "time" } }),
      segment({ section_id: "amrap:rest-after", between_sections: true, phase: "rest" }),
    ]);

    expect([...sections.keys()]).toEqual(["amrap", "emom", "tabata"]);
    expect(sections.get("amrap")).toEqual({ planned_ms: 600_000, section_name: "AMRAP" });
    expect(sections.get("emom")?.planned_ms).toBe(600_000);
    // work 20 + off 10 + work 20
    expect(sections.get("tabata")?.planned_ms).toBe(50_000);
  });

  it("asks only about sections that ran short of their clock, beyond the last tick", () => {
    const segments = [segment({ section_id: "a" }), segment({ section_id: "b" }), segment({ section_id: "c" })];

    expect(stoppedEarlySections(segments, { a: 360_000, b: 599_400, c: 600_000 })).toEqual([
      { section_id: "a", section_name: "A", ran_ms: 360_000, planned_ms: 600_000 },
    ]);
    // A section never reached ran 0 of its clock.
    expect(stoppedEarlySections([segment({ section_id: "a" })], {})).toEqual([
      { section_id: "a", section_name: "A", ran_ms: 0, planned_ms: 600_000 },
    ]);
  });
});
