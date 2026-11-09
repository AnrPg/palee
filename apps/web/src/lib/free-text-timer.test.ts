import { describe, expect, it } from "vitest";

import canonicalFixtures from "./timer-preset-canonical-fixtures.json";
import fixtures from "./timer-preset-fixtures.json";
import {
  buildFreeTextSegments,
  canonicalTimerPreset,
  freeTextPosition,
  parseFreeTextTimerPreset,
  runElapsedMs,
  sameTimerPreset,
  timerChipLabel,
} from "./free-text-timer";

describe("free-text timer", () => {
  it("runs a Tabata as work/rest intervals without a trailing rest", () => {
    const segments = buildFreeTextSegments({ format: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 2 });
    expect(segments.map((segment) => [segment.phase, segment.duration_seconds])).toEqual([
      ["work", 20],
      ["rest", 10],
      ["work", 20],
    ]);

    const inRest = freeTextPosition(segments, 25_000);
    expect(inRest.index).toBe(1);
    expect(inRest.clock.remainingMs).toBe(5_000);
    expect(inRest.finished).toBe(false);

    const done = freeTextPosition(segments, 99_000);
    expect(done.finished).toBe(true);
    expect(done.totalElapsedMs).toBe(50_000);
  });

  it("counts EMOM windows on one interval cycle", () => {
    const [emom] = buildFreeTextSegments({ format: "emom", interval_seconds: 60, rounds: 10 });
    const position = freeTextPosition([emom!], 125_000);
    expect(position.clock.window).toMatchObject({ index: 3, count: 10 });
    expect(position.clock.remainingMs).toBe(55_000);
  });

  it("keeps a stopwatch running without an end", () => {
    const position = freeTextPosition(buildFreeTextSegments({ format: "untimed" }), 3_600_000);
    expect(position.finished).toBe(false);
    expect(position.clock.elapsedMs).toBe(3_600_000);
  });

  it("derives elapsed time from wall-clock timestamps", () => {
    expect(runElapsedMs({ startedAt: 1_000, carriedMs: 5_000 }, 4_000)).toBe(8_000);
    expect(runElapsedMs({ startedAt: null, carriedMs: 5_000 }, 4_000)).toBe(5_000);
  });

  it("rejects malformed presets from metadata", () => {
    expect(parseFreeTextTimerPreset({ format: "bogus" })).toBeNull();
    expect(parseFreeTextTimerPreset({ format: "amrap", duration_seconds: -5 })).toMatchObject({
      format: "amrap",
      duration_seconds: null,
    });
  });
});

describe("timer preset parity with the API", () => {
  it.each(fixtures.cases.map((entry) => [entry.preset.format, entry] as const))("builds %s like the server", (_format, entry) => {
    const segments = buildFreeTextSegments(parseFreeTextTimerPreset(entry.preset)!);
    expect(segments.map((segment) => [segment.kind, segment.phase, segment.duration_seconds, segment.total_rounds])).toEqual(
      entry.segments,
    );
  });

  it("ADR-571: reduces a preset to its canonical form, as the API does", () => {
    for (const item of canonicalFixtures.cases) {
      expect(canonicalTimerPreset(item.preset), JSON.stringify(item.preset)).toEqual(item.canonical);
    }
  });

  it("ADR-571: compares timers by what they run", () => {
    expect(sameTimerPreset({ format: "emom" }, { format: "emom", interval_seconds: 60, rounds: 10, rest_seconds: 5 })).toBe(true);
    expect(sameTimerPreset({ format: "emom", rounds: 4 }, { format: "emom", rounds: 5 })).toBe(false);
    expect(sameTimerPreset({ format: "untimed" }, null)).toBe(false);
  });

  it("ADR-571: names a chip the way coaches say it", () => {
    expect(timerChipLabel({ format: "amrap", duration_seconds: 600 }, "AMRAP")).toBe("AMRAP 10");
    expect(timerChipLabel({ format: "amrap", duration_seconds: 630 }, "AMRAP")).toBe("AMRAP 10:30");
    expect(timerChipLabel({ format: "emom", interval_seconds: 60, rounds: 4 }, "EMOM")).toBe("EMOM 4");
    expect(timerChipLabel({ format: "emom", interval_seconds: 120, rounds: 10 }, "EMOM")).toBe("E2MOM 20");
    expect(timerChipLabel({ format: "emom", interval_seconds: 90, rounds: 8 }, "EMOM")).toBe("EMOM 8 × 1:30");
    expect(timerChipLabel({ format: "for_time", duration_seconds: 720 }, "For Time")).toBe("For Time 12′");
    expect(timerChipLabel({ format: "for_time" }, "For Time")).toBe("For Time");
    expect(timerChipLabel({ format: "tabata" }, "Tabata")).toBe("Tabata 20/10 × 8");
    expect(timerChipLabel({ format: "death_by" }, "Death By")).toBe("Death By");
  });
});
