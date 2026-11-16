import { describe, expect, it } from "vitest";

import { NO_TIME_PRESET } from "@/lib/free-text-timer";
import { editorSectionsFrom, emptySection, withSectionTimer } from "@/lib/text-sections";

import { findTextTimers } from "./parse";
import { effectiveTimer, FOLLOW_TEXT, loadTimerFrom } from "./text-timer";

const TEXT = "EMOM 10\n5 cleans\n\nAMRAP 12\n10 burpees";
const emom = { format: "emom", interval_seconds: 60, rounds: 10 } as const;
const amrap = { format: "amrap", duration_seconds: 720 } as const;

describe("the timer a text WOD runs (ADR-650)", () => {
  it("follows the text: the first timer, or the picked one, or none", () => {
    const found = findTextTimers(TEXT);
    expect(effectiveTimer(found, FOLLOW_TEXT, null, null)).toEqual(emom);
    expect(effectiveTimer(found, { from: "text", pick: 1 }, null, null)).toEqual(amrap);
    expect(effectiveTimer(found, { from: "text", pick: 2 }, null, null)).toEqual(emom);
    expect(effectiveTimer(findTextTimers("10 burpees"), FOLLOW_TEXT, null, null)).toBeNull();
  });

  it("keeps the coach's own timer whatever the text says", () => {
    const own = { format: "for_time", duration_seconds: 900 } as const;
    expect(effectiveTimer(findTextTimers(TEXT), { from: "hand", pick: 0 }, own, null)).toEqual(own);
  });

  it("reads a saved timer back as following the text only when the text asks for it", () => {
    expect(loadTimerFrom(TEXT, amrap, null)).toEqual({ from: "text", pick: 1 });
    expect(loadTimerFrom(TEXT, { format: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 8 }, null)).toEqual({ from: "hand", pick: 0 });
    expect(loadTimerFrom("10 burpees", null, null)).toEqual(FOLLOW_TEXT);
    // A draft saved before ADR-650 with no timer and a format in its text keeps having none.
    expect(loadTimerFrom(TEXT, null, null)).toEqual({ from: "hand", pick: 0 });
    expect(loadTimerFrom(TEXT, NO_TIME_PRESET, "untimed")).toEqual({ from: "hand", pick: 0 });
  });
});

describe("a text section's timer (ADR-650, Ζ1)", () => {
  it("picks the chip its text asks for, and «Χωρίς χρόνο» when the text no longer does", () => {
    const section = withSectionTimer({ ...emptySection(), body: "AMRAP 12\n10 burpees" });
    expect(section.preset).toEqual(amrap);
    expect(withSectionTimer({ ...section, body: "10 burpees" }).preset).toEqual(NO_TIME_PRESET);
  });

  it("keeps a timer chosen by hand", () => {
    const own = { format: "emom", interval_seconds: 120, rounds: 5 } as const;
    const section = withSectionTimer({ ...emptySection(), body: "AMRAP 12", preset: own, timerFrom: { from: "hand", pick: 0 } });
    expect(section.preset).toEqual(own);
  });

  it("loads saved sections with their source", () => {
    const [fromText, own] = editorSectionsFrom(
      {
        authoring_mode: "sectioned_text",
        sections: [
          { name: "A", free_text_body: "AMRAP 12", timer_preset: amrap } as never,
          { name: "B", free_text_body: "AMRAP 12", timer_preset: NO_TIME_PRESET } as never,
        ],
      },
      null,
    );
    expect(fromText!.timerFrom).toEqual({ from: "text", pick: 0 });
    expect(own!.timerFrom).toEqual({ from: "hand", pick: 0 });
  });
});
