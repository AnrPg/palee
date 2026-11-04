import { describe, expect, it } from "vitest";

import type { Pacer, RankStanding } from "@/api/body-devices";

import {
  addMealFood,
  beltColor,
  deltaTone,
  formatDelta,
  hasPastSelf,
  headlineDelta,
  latestDelta,
  normalizeBarcode,
  nutrientsFrom,
  parseNutrient,
  paceLane,
  paceRows,
  promotionChoices,
  rankCriteria,
  rankProgress,
  rankSkills,
  skillTicks,
} from "./body-devices";

const checkpoint = (round: number, ghost: number, at: number | null, delta: number | null) => ({
  key: `0:work:${round}:0`,
  section_ordinal: 0,
  section_name: "AMRAP 12",
  phase: "work" as const,
  round,
  ghost_at_ms: ghost,
  ghost_lap_ms: 60_000,
  at_ms: at,
  lap_ms: null,
  delta_ms: delta,
});

const pacer = (overrides: Partial<Pacer> = {}): Pacer => ({
  execution_id: "e2",
  previous: { execution_id: "e1", completed_at_utc: "2026-09-12T07:00:00Z", completed_at_tz: "Europe/Athens", same_workout: true },
  precision: "rounds",
  checkpoints: [checkpoint(1, 60_000, 55_000, -5_000), checkpoint(2, 120_000, 118_000, -2_000), checkpoint(3, 180_000, 190_000, 10_000), checkpoint(4, 240_000, null, null)],
  sections: [{ section_ordinal: 0, section_name: "AMRAP 12", ghost_ms: 720_000, current_ms: null, delta_ms: null }],
  ghost_total_ms: 720_000,
  current_total_ms: null,
  total_delta_ms: null,
  ...overrides,
});

describe("past self (ADR-374)", () => {
  it("formats a difference with a real minus and words without judgement", () => {
    expect(formatDelta(-5_000)).toBe("−0:05");
    expect(formatDelta(72_400)).toBe("+1:12");
    expect(formatDelta(300)).toBe("0:00");
    expect(deltaTone(-5_000)).toBe("ahead");
    expect(deltaTone(12_000)).toBe("behind");
    expect(deltaTone(400)).toBe("level");
  });

  it("needs a previous attempt with checkpoints", () => {
    expect(hasPastSelf(null)).toBe(false);
    expect(hasPastSelf(pacer({ previous: null }))).toBe(false);
    expect(hasPastSelf(pacer({ checkpoints: [] }))).toBe(false);
    expect(hasPastSelf(pacer())).toBe(true);
  });

  it("places both dots on one bar: the clock moves the previous one, marks move yours", () => {
    expect(paceLane(pacer(), 150_000)).toEqual({ you: 0.75, past: 0.5 });
  });

  it("shows the latest finished mark and, once done, the whole attempt", () => {
    expect(latestDelta(pacer())?.round).toBe(3);
    expect(headlineDelta(pacer())).toBe(10_000);
    expect(headlineDelta(pacer({ total_delta_ms: -4_000 }))).toBe(-4_000);
  });

  it("groups rounds and shows each group's own gain or loss", () => {
    const rows = paceRows(pacer(), 2);
    expect(rows.map((row) => [row.from, row.to, row.deltaMs])).toEqual([
      [1, 2, -2_000],
      [3, 4, 12_000],
    ]);
  });

  it("uses sections when the previous attempt had no rounds", () => {
    const rows = paceRows(pacer({ precision: "sections", sections: [{ section_ordinal: 0, section_name: "21-15-9", ghost_ms: 264_000, current_ms: 250_000, delta_ms: -14_000 }] }));
    expect(rows).toEqual([{ key: "s0", kind: "section", name: "21-15-9", deltaMs: -14_000 }]);
  });
});

describe("the nutrition table of an own food (ADR-421)", () => {
  it("reads grams per 100 g, a comma as the decimal mark, blank as nothing", () => {
    expect(parseNutrient(" 12,5 ")).toBe(12.5);
    expect(parseNutrient("0")).toBe(0);
    expect(parseNutrient("")).toBeNull();
    expect(parseNutrient("101")).toBe("invalid");
    expect(parseNutrient("-1")).toBe("invalid");
    expect(parseNutrient("abc")).toBe("invalid");
  });

  it("collects what to send and which fields are wrong", () => {
    expect(nutrientsFrom({ proteins: "17", fat: "21,5", salt: "" })).toEqual({ nutrients: { proteins: 17, fat: 21.5 }, invalid: [] });
    expect(nutrientsFrom({ sugars: "300" })).toEqual({ nutrients: {}, invalid: ["sugars"] });
  });
});

describe("barcodes and meal foods (ADR-376)", () => {
  it("accepts EAN-13, EAN-8 and UPC-A with a correct check digit only", () => {
    expect(normalizeBarcode("5 201 054 017 104")).toBe("5201054017104");
    expect(normalizeBarcode("96385074")).toBe("96385074");
    expect(normalizeBarcode("036000291452")).toBe("036000291452");
    expect(normalizeBarcode("5201054017105")).toBeNull();
    expect(normalizeBarcode("12345")).toBeNull();
  });

  it("keeps one line per product and at most ten", () => {
    const yogurt = { name: "Yogurt", barcode: "5201054017104" };
    const twice = addMealFood(addMealFood([], yogurt), { ...yogurt, portion: "protein" });
    expect(twice).toEqual([{ ...yogurt, portion: "protein" }]);
    const many = Array.from({ length: 12 }, (_, index) => ({ name: `F${index}` })).reduce(addMealFood, [] as { name: string }[]);
    expect(many).toHaveLength(10);
  });
});

describe("belts and levels (ADR-377)", () => {
  const rank = (id: string, name: string, maxStripes = 4) => ({ id, position: 0, name, color: "blue" as const, max_stripes: maxStripes, requirements: {}, scale_level_slug: null });
  const standing = (overrides: Partial<RankStanding> = {}): RankStanding => ({
    ladder: { id: "l", name: "BJJ", discipline: "bjj_grappling", style: "belt", class_type_ids: [], ready_criteria: ["classes", "days"], ranks: [rank("w", "White"), rank("b", "Blue")] },
    current: { award_id: "a", rank: rank("w", "White"), stripes: 2, awarded_on: "2025-03-01" },
    next: rank("b", "Blue"),
    progress: { rank_id: "b", classes: { done: 40, needed: 80 }, days: { done: 730, needed: 730 }, skills: [], ready: false },
    history: [],
    ...overrides,
  });

  it("maps a belt colour to its theme token", () => {
    expect(beltColor("purple")).toBe("var(--belt-purple)");
    expect(beltColor(null)).toBe("var(--panel-muted)");
  });

  it("averages the counted requirements", () => {
    expect(rankProgress(standing())).toBe(0.75);
    expect(rankProgress(standing({ progress: null }))).toBeNull();
  });

  it("counts only what the ladder counts, skills by their stable id", () => {
    const blue = { ...rank("b", "Blue"), requirements: { skills: ["Armbar", "Triangle"], skill_ids: ["s1", "s2"], skill_notes: [null, "Both sides"] } };
    const skillsOnly = standing({
      next: blue,
      progress: {
        rank_id: "b",
        classes: { done: 0, needed: 80 },
        days: { done: 0, needed: 730 },
        skills: ["Armbar", "Triangle"],
        // Ticked as an older text: the id still matches.
        skills_checked: [{ skill: "Armbar (old)", skill_id: "s1", checked_on: "2026-10-01", note: null }],
        criteria: ["skills"],
        ready: false,
      },
    });
    expect(rankCriteria(skillsOnly)).toEqual(["skills"]);
    expect(rankProgress(skillsOnly)).toBe(0.5);
    expect(skillTicks(skillsOnly).map((tick) => [tick.name, tick.checked, tick.note])).toEqual([
      ["Armbar", true, null],
      ["Triangle", false, "Both sides"],
    ]);
    expect(rankCriteria(standing({ ladder: { ...standing().ladder, ready_criteria: "x" as never } }))).toEqual(["days", "classes"]);
    expect(rankSkills({ requirements: { skills: "nope" as never } })).toEqual([]);
  });

  it("offers a stripe or the next rank, never a lower one", () => {
    expect(promotionChoices(standing()).map((choice) => [choice.kind, choice.rank.id, choice.stripes])).toEqual([
      ["stripe", "w", 3],
      ["rank", "b", 0],
    ]);
    const full = standing({ current: { award_id: "a", rank: rank("w", "White"), stripes: 4, awarded_on: "2025-03-01" } });
    expect(promotionChoices(full).map((choice) => choice.kind)).toEqual(["rank"]);
    expect(promotionChoices(standing({ current: null, next: null })).map((choice) => choice.rank.id)).toEqual(["w"]);
  });
});
