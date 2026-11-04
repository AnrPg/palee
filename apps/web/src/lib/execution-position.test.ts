import { describe, expect, it } from "vitest";

import type { TimerSegment } from "@/api/executions";
import { positionMetadata, timerClosedMetadata } from "@/lib/execution-position";

const segment = (more: Partial<TimerSegment>): TimerSegment =>
  ({ section_id: "a1b2", format: "amrap", kind: "countdown", duration_seconds: 600, ...more }) as TimerSegment;

const state = (status: string, segments: TimerSegment[], elapsed = 0, index = 0) => ({
  status,
  currentSegmentIndex: index,
  segments,
  currentElapsedMs: () => elapsed,
});

describe("positionMetadata", () => {
  it("leaves out ids the server would not accept as tokens", () => {
    expect(positionMetadata(state("active", [segment({ section_id: "x:transition" })]))).toEqual({
      segment_index: 0,
      format: "amrap",
    });
  });
});

describe("timerClosedMetadata (ADR-549)", () => {
  it("says where the athlete left and how much clock was left", () => {
    expect(timerClosedMetadata(state("active", [segment({})], 240_400), Date.now())).toEqual({
      segment_index: 0,
      section_id: "a1b2",
      format: "amrap",
      elapsed_ms: 240_400,
      remaining_ms: 359_600,
    });
  });

  it("has no remaining time on a count-up", () => {
    const metadata = timerClosedMetadata(state("paused", [segment({ kind: "countup" })], 1_000), Date.now());
    expect(metadata).not.toHaveProperty("remaining_ms");
  });

  it("is null before the start and after the finish", () => {
    expect(timerClosedMetadata(state("idle", [segment({})]), Date.now())).toBeNull();
    expect(timerClosedMetadata(state("completed", [segment({})]), Date.now())).toBeNull();
  });
});
