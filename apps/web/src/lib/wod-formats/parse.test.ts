import { describe, expect, it } from "vitest";

import { canonicalTimerPreset, sameTimerPreset, type FreeTextTimerPreset } from "@/lib/free-text-timer";

import { TIMED_WOD_FORMATS, WOD_FORMATS } from "./catalog";
import { formatCompletions, timerText } from "./complete";
import { findTextTimers, readFormatLine } from "./parse";

const timer = (line: string) => readFormatLine(line)?.preset ?? null;
const expectTimer = (line: string, preset: FreeTextTimerPreset) => expect(timer(line)).toEqual(canonicalTimerPreset(preset));

describe("the canonical WOD format list (ADR-650)", () => {
  it("holds every flow and every preset of the structured editor", () => {
    expect(WOD_FORMATS.map((format) => format.key)).toEqual([
      "sets", "for_time", "amrap", "emom", "intervals", "rest",
      "tabata", "billat", "hrr", "death_by", "even_odd", "complex_emom", "edt", "chipper", "21_15_9", "ladder",
      "calorie_target", "to_failure", "superset", "cluster", "drop_set", "rest_pause", "interrupt",
    ]);
  });

  it("takes the agreed preset values", () => {
    expect(timer("Tabata")).toEqual({ format: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 8 });
    expect(timer("Billat")).toEqual({ format: "custom_hiit", work_seconds: 30, rest_seconds: 30, rounds: 10 });
    expect(timer("HRR")).toEqual({ format: "custom_hiit", work_seconds: 180, rounds: 3 });
    expect(timer("EDT")).toEqual({ format: "amrap", duration_seconds: 900 });
    expect(timer("Death by")).toEqual({ format: "death_by", interval_seconds: 60 });
  });

  it("sets no timer for sets, structures, rest and add-ons", () => {
    const untimed = WOD_FORMATS.filter((format) => !TIMED_WOD_FORMATS.includes(format)).map((format) => format.key);
    expect(untimed).toEqual(["sets", "rest", "to_failure", "superset", "cluster", "drop_set", "rest_pause", "interrupt"]);
    for (const line of ["Strength", "Rest 2:00", "Superset", "Drop set", "Σετ 5x5"]) expect(timer(line)).toBeNull();
  });
});

describe("readFormatLine", () => {
  it.each([
    ["AMRAP 12", { format: "amrap", duration_seconds: 720 }],
    ["amrap 12'", { format: "amrap", duration_seconds: 720 }],
    ["AMRAP in 20 minutes", { format: "amrap", duration_seconds: 1200 }],
    ["12' AMRAP", { format: "amrap", duration_seconds: 720 }],
    ["AMRAP 12: 10 burpees, 15 KBS", { format: "amrap", duration_seconds: 720 }],
    ["Όσους γύρους 15'", { format: "amrap", duration_seconds: 900 }],
    ["AMRAP 7:30", { format: "amrap", duration_seconds: 450 }],
    ["EMOM 10", { format: "emom", interval_seconds: 60, rounds: 10 }],
    ["EMOM x 12", { format: "emom", interval_seconds: 60, rounds: 12 }],
    ["E2MOM 20", { format: "emom", interval_seconds: 120, rounds: 10 }],
    ["E3MOM x 5", { format: "emom", interval_seconds: 180, rounds: 5 }],
    ["E90S x 8", { format: "emom", interval_seconds: 90, rounds: 8 }],
    ["Every 2' x 6", { format: "emom", interval_seconds: 120, rounds: 6 }],
    ["Every 1:30 for 12'", { format: "emom", interval_seconds: 90, rounds: 8 }],
    ["Κάθε 3' x 5", { format: "emom", interval_seconds: 180, rounds: 5 }],
    ["Κάθε λεπτό για 10'", { format: "emom", interval_seconds: 60, rounds: 10 }],
    ["20 min EMOM", { format: "emom", interval_seconds: 60, rounds: 20 }],
    ["Alternating EMOM 12", { format: "emom", interval_seconds: 60, rounds: 12 }],
    ["Tabata x 6", { format: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 6 }],
    ["Tabata 20/10 × 8", { format: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 8 }],
    ["40/20 x 8", { format: "custom_hiit", work_seconds: 40, rest_seconds: 20, rounds: 8 }],
    ["30 on 30 off x 10", { format: "custom_hiit", work_seconds: 30, rest_seconds: 30, rounds: 10 }],
    ["Intervals 1:00/1:00 x 5", { format: "custom_hiit", work_seconds: 60, rest_seconds: 60, rounds: 5 }],
    ["20/10 x 8", { format: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 8 }],
    ["For time", { format: "for_time" }],
    ["For time: 50 wall balls, 50 box jumps", { format: "for_time" }],
    ["For time, cap 15", { format: "for_time", duration_seconds: 900 }],
    ["FT (TC 12')", { format: "for_time", duration_seconds: 720 }],
    ["For Time 15′", { format: "for_time", duration_seconds: 900 }],
    ["Για χρόνο, όριο 20'", { format: "for_time", duration_seconds: 1200 }],
    ["5 RFT", { format: "for_time" }],
    ["3 rounds for time", { format: "for_time" }],
    ["21-15-9", { format: "for_time" }],
    ["21 - 15 - 9 thrusters & pull-ups", { format: "for_time" }],
    ["Chipper, cap 30", { format: "for_time", duration_seconds: 1800 }],
    ["Death by burpees", { format: "death_by", interval_seconds: 60 }],
    ["Death by thrusters every 2'", { format: "death_by", interval_seconds: 120 }],
    ["Death by 10m shuttle", { format: "death_by", interval_seconds: 60 }],
    ["- AMRAP 12", { format: "amrap", duration_seconds: 720 }],
    ["B) EMOM 10", { format: "emom", interval_seconds: 60, rounds: 10 }],
    ["Part B: EMOM 10", { format: "emom", interval_seconds: 60, rounds: 10 }],
    ["Metcon - AMRAP 20", { format: "amrap", duration_seconds: 1200 }],
    ["Even odd 10", { format: "emom", interval_seconds: 60, rounds: 10 }],
    ["Μονά ζυγά 12", { format: "emom", interval_seconds: 60, rounds: 12 }],
    ["Complex EMOM 15", { format: "emom", interval_seconds: 60, rounds: 15 }],
    ["EDT 20", { format: "amrap", duration_seconds: 1200 }],
    ["Billat x 12", { format: "custom_hiit", work_seconds: 30, rest_seconds: 30, rounds: 12 }],
    ["Fran", { format: "for_time" }],
    ["Πυραμίδα", { format: "for_time" }],
    ["Calorie target", { format: "for_time" }],
    ["TC 12'", null],
  ] as [string, FreeTextTimerPreset | null][])("%s", (line, preset) => (preset ? expectTimer(line, preset) : expect(timer(line)).toBeNull()));

  it.each(["AMRAP", "EMOM", "Every minute", "Intervals", "E2MOM 15"])("%s needs its number", (line) => {
    const read = readFormatLine(line);
    expect(read?.preset).toBeNull();
    expect(read?.incomplete).toBe(true);
  });

  it.each([
    "10 wall balls",
    "Back squat 5x5",
    "Row 500m",
    "Run 400m, rest 1:00",
    "50 cal row",
    "Target: smooth reps",
    "Ftness",
    "Amrapolis",
    "Coach notes: scale to ring rows",
  ])("reads no timer from «%s»", (line) => expect(timer(line)).toBeNull());

  it("reads the screen's own labels too", () => {
    expect(readFormatLine("Leiter, cap 12", { ladder: "Leiter / Pyramide" })?.preset).toEqual({ format: "for_time", duration_seconds: 720 });
  });
});

describe("findTextTimers", () => {
  it("lists every timer of a text in order, and the formats missing their number", () => {
    const found = findTextTimers("Strength\nBack squat 5x5\n\nEMOM 10\n5 cleans\n\nAMRAP\n10 burpees\n\nAMRAP 12\n10 pull-ups");
    expect(found.timers.map((item) => [item.line, item.key])).toEqual([[3, "emom"], [9, "amrap"]]);
    expect(found.incomplete).toEqual([{ line: 6, key: "amrap" }]);
  });
});

describe("formatCompletions", () => {
  const frequent: FreeTextTimerPreset[] = [
    { format: "amrap", duration_seconds: 720 },
    { format: "emom", interval_seconds: 120, rounds: 10 },
    { format: "for_time", duration_seconds: 900 },
  ];

  it("offers the coach's most used timers first, then the formats", () => {
    expect(formatCompletions("am", { frequent }).map((item) => [item.text, item.frequent])).toEqual([
      ["AMRAP 12", true],
      ["AMRAP ", false],
    ]);
    expect(formatCompletions("e2", { frequent }).map((item) => item.text)).toEqual(["E2MOM 20", "E2MOM "]);
    expect(formatCompletions("tab").map((item) => item.text)).toEqual(["Tabata"]);
    expect(formatCompletions("για χ").map((item) => item.text)).toEqual(["Για χρόνο"]);
    expect(formatCompletions("dea").map((item) => item.text)).toEqual(["Death by"]);
  });

  it("replaces only the words after a bullet or a label", () => {
    expect(formatCompletions("Part B: em")[0]).toMatchObject({ text: "EMOM ", from: 8 });
  });

  it("keeps quiet on a complete timer and on long lines", () => {
    expect(formatCompletions("AMRAP 12")).toEqual([]);
    expect(formatCompletions("10 burpees and then some more")).toEqual([]);
  });

  it("writes every timer so that it reads back the same", () => {
    const presets: FreeTextTimerPreset[] = [
      ...frequent,
      { format: "emom", interval_seconds: 60, rounds: 4 },
      { format: "emom", interval_seconds: 90, rounds: 8 },
      { format: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 8 },
      { format: "custom_hiit", work_seconds: 40, rest_seconds: 20, rounds: 6 },
      { format: "for_time" },
      { format: "death_by", interval_seconds: 60 },
      { format: "death_by", interval_seconds: 120 },
    ];
    for (const preset of presets) {
      const text = timerText(preset)!;
      expect(sameTimerPreset(timer(text), preset), text).toBe(true);
    }
  });
});

describe("docs/product/wod-formats.md", () => {
  it("lists exactly the formats of the code", async () => {
    const { readFileSync } = await import("node:fs");
    const { resolve } = await import("node:path");
    const doc = readFileSync(resolve(__dirname, "../../../../../docs/product/wod-formats.md"), "utf8");
    const keys = [...doc.matchAll(/^\| `([a-z0-9_]+)` \|/gmu)].map((match) => match[1]);
    expect(keys).toEqual(WOD_FORMATS.map((format) => format.key));
  });
});

describe("formats in every language Palee speaks (ADR-650)", () => {
  it.each<[string, FreeTextTimerPreset]>([
    ["Auf Zeit, Zeitlimit 15", { format: "for_time", duration_seconds: 900 }],
    ["alle 2 Min x 6", { format: "emom", interval_seconds: 120, rounds: 6 }],
    ["AMRAP 12 Min", { format: "amrap", duration_seconds: 720 }],
    ["toutes les 2 min x 5", { format: "emom", interval_seconds: 120, rounds: 5 }],
    ["Toutes les minutes 10", { format: "emom", interval_seconds: 60, rounds: 10 }],
    ["Por tiempo, límite 20", { format: "for_time", duration_seconds: 1200 }],
    ["Cada 2 min x 5", { format: "emom", interval_seconds: 120, rounds: 5 }],
    ["Ogni 2 minuti x 6", { format: "emom", interval_seconds: 120, rounds: 6 }],
    ["Elke 2 min x 6", { format: "emom", interval_seconds: 120, rounds: 6 }],
    ["A cada 2 min x 6", { format: "emom", interval_seconds: 120, rounds: 6 }],
    ["Каждую минуту 10", { format: "emom", interval_seconds: 60, rounds: 10 }],
    ["EMOM х 12", { format: "emom", interval_seconds: 60, rounds: 12 }],
    ["На всеки 2 мин x 6", { format: "emom", interval_seconds: 120, rounds: 6 }],
    ["כל 2 דקות x 6", { format: "emom", interval_seconds: 120, rounds: 6 }],
  ])("%s", (line, preset) => expectTimer(line, preset));

  it.each(["Pour le temps", "Per tempo", "Voor tijd", "Por tempo", "На время", "За време", "לזמן", "على الوقت"])("%s is For Time", (line) =>
    expectTimer(line, { format: "for_time" }),
  );

  it("keeps the labels equal to the structured editor's translated names", async () => {
    const { readFileSync } = await import("node:fs");
    const { resolve } = await import("node:path");
    const { LOCALE_WORDS } = await import("./locale-words");
    for (const [locale, words] of Object.entries(LOCALE_WORDS)) {
      const core = JSON.parse(readFileSync(resolve(__dirname, `../../../messages/${locale}.json`), "utf8")).PlanCore;
      for (const format of WOD_FORMATS) {
        const [group, key] = format.labelKey.split(".").slice(1) as ["flow" | "preset", string];
        expect([locale, format.key, words.labels[format.key]]).toEqual([locale, format.key, core[group][key]]);
      }
    }
  });
});
