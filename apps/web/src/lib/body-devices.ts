import type { FoodPortion, PaceCheckpoint, Pacer, Rank, RankColor, RankStanding } from "@/api/body-devices";

// v3.2 «Body and devices» (ADR-374..377): pure helpers for the screens.

/** «−0:05» ahead, «+0:12» behind, «0:00» level; minutes:seconds, the minus a real minus sign. */
export function formatDelta(deltaMs: number): string {
  const seconds = Math.round(Math.abs(deltaMs) / 1000);
  const text = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
  if (seconds === 0) return text;
  return `${deltaMs < 0 ? "−" : "+"}${text}`;
}

export type DeltaTone = "ahead" | "behind" | "level";

export function deltaTone(deltaMs: number): DeltaTone {
  const seconds = Math.round(deltaMs / 1000);
  return seconds < 0 ? "ahead" : seconds > 0 ? "behind" : "level";
}

/** Whether there is a previous attempt to race (and a line to draw). */
export function hasPastSelf(pacer: Pacer | null | undefined): pacer is Pacer {
  return Boolean(pacer?.previous && pacer.checkpoints.length > 0);
}

/**
 * ADR-374 (mockup d7live A): where «Εσύ» and «Η προηγούμενη φορά» are on one
 * thin bar, 0–1. The previous attempt moves with the clock; this attempt moves
 * with the marks it has made.
 */
export function paceLane(pacer: Pacer, elapsedMs: number): { you: number; past: number } {
  const total = pacer.checkpoints.length;
  if (total === 0) return { you: 0, past: 0 };
  const reached = pacer.checkpoints.filter((checkpoint) => checkpoint.at_ms !== null && checkpoint.at_ms !== undefined).length;
  const passed = pacer.checkpoints.filter((checkpoint) => checkpoint.ghost_at_ms <= elapsedMs).length;
  return { you: reached / total, past: passed / total };
}

/** The last checkpoint this attempt reached: the delta shown at the end of a round. */
export function latestDelta(pacer: Pacer): PaceCheckpoint | null {
  const reached = pacer.checkpoints.filter((checkpoint) => typeof checkpoint.delta_ms === "number");
  return reached.length > 0 ? reached[reached.length - 1] : null;
}

export type PaceRow = { key: string; kind: "rounds" | "section"; from?: number; to?: number; name?: string | null; deltaMs: number | null };

/**
 * ADR-374 (mockup d7res A): the rows under the headline. Rounds in up to four
 * groups when the previous attempt had rounds and the WOD has one section;
 * otherwise one row per section.
 */
export function paceRows(pacer: Pacer, maxGroups = 4): PaceRow[] {
  const rounds = pacer.checkpoints.filter((checkpoint) => checkpoint.round > 0 && checkpoint.phase === "work");
  const sections = pacer.sections;
  if (pacer.precision === "rounds" && sections.length <= 1 && rounds.length > 1) {
    const size = Math.ceil(rounds.length / maxGroups);
    const rows: PaceRow[] = [];
    // Each group shows its own gain or loss: its last delta minus the one before it.
    let before = 0;
    for (let start = 0; start < rounds.length; start += size) {
      const group = rounds.slice(start, start + size);
      const last = [...group].reverse().find((checkpoint) => typeof checkpoint.delta_ms === "number");
      const lastDelta = last ? (last.delta_ms as number) : null;
      rows.push({
        key: `r${start}`,
        kind: "rounds",
        from: group[0].round,
        to: group[group.length - 1].round,
        deltaMs: lastDelta === null ? null : lastDelta - before,
      });
      if (lastDelta !== null) before = lastDelta;
    }
    return rows;
  }
  return sections.map((section) => ({
    key: `s${section.section_ordinal}`,
    kind: "section",
    name: section.section_name ?? null,
    deltaMs: typeof section.delta_ms === "number" ? section.delta_ms : null,
  }));
}

/** The headline: the whole attempt once finished, else the latest mark. */
export function headlineDelta(pacer: Pacer): number | null {
  if (typeof pacer.total_delta_ms === "number") return pacer.total_delta_ms;
  const latest = latestDelta(pacer);
  return latest && typeof latest.delta_ms === "number" ? latest.delta_ms : null;
}

export const PACER_COMPARE_KEY = "palee:pacer-compare";
export type PacerCompare = "previous" | "hidden";

/** The person's choice, remembered on this device (mockup: «θυμάται την επιλογή»). */
export function readPacerCompare(): PacerCompare {
  try {
    return window.localStorage.getItem(PACER_COMPARE_KEY) === "hidden" ? "hidden" : "previous";
  } catch {
    return "previous";
  }
}

export function writePacerCompare(value: PacerCompare) {
  try {
    window.localStorage.setItem(PACER_COMPARE_KEY, value);
  } catch {
    // Private mode or blocked storage: the choice lasts for this visit only.
  }
}

// ADR-376: barcodes.

/** GS1 check digit for EAN-8, UPC-A, EAN-13 and GTIN-14; spaces are ignored. */
export function normalizeBarcode(raw: string): string | null {
  const digits = raw.replace(/\s+/g, "");
  if (!/^\d{8}$|^\d{12,14}$/.test(digits)) return null;
  const body = digits.slice(0, -1);
  const sum = [...body].reverse().reduce((acc, char, index) => acc + Number(char) * (index % 2 === 0 ? 3 : 1), 0);
  const check = (10 - (sum % 10)) % 10;
  return check === Number(digits[digits.length - 1]) ? digits : null;
}

export const FOOD_PORTIONS: FoodPortion[] = ["protein", "carbs", "veg", "fat"];

export type MealFood = { name: string; barcode?: string; custom_food_id?: string; portion?: FoodPortion };

/** At most ten foods in a meal, one per barcode or own food. */
export function addMealFood(foods: MealFood[], food: MealFood): MealFood[] {
  const same = (entry: MealFood) =>
    (food.barcode && entry.barcode === food.barcode) || (food.custom_food_id && entry.custom_food_id === food.custom_food_id);
  return [...foods.filter((entry) => !same(entry)), food].slice(-10);
}

// ADR-421: the nutrition table of «Δικό μου τρόφιμο», grams per 100 g.
export const FOOD_NUTRIENTS = ["proteins", "carbohydrates", "fat", "fiber", "sugars", "salt"] as const;
export type FoodNutrientKey = (typeof FOOD_NUTRIENTS)[number];

/** A typed amount: null when blank, "invalid" unless 0–100 (a comma works as the decimal mark). */
export function parseNutrient(raw: string): number | null | "invalid" {
  const text = raw.trim().replace(",", ".");
  if (text === "") return null;
  if (!/^\d+(\.\d+)?$/.test(text)) return "invalid";
  const value = Number(text);
  return value >= 0 && value <= 100 ? value : "invalid";
}

/** The nutrients to send and the fields to mark; nothing to send when every field is blank. */
export function nutrientsFrom(fields: Partial<Record<FoodNutrientKey, string>>): {
  nutrients: Partial<Record<FoodNutrientKey, number>>;
  invalid: FoodNutrientKey[];
} {
  const nutrients: Partial<Record<FoodNutrientKey, number>> = {};
  const invalid: FoodNutrientKey[] = [];
  for (const key of FOOD_NUTRIENTS) {
    const value = parseNutrient(fields[key] ?? "");
    if (value === "invalid") invalid.push(key);
    else if (value !== null) nutrients[key] = value;
  }
  return { nutrients, invalid };
}

// ADR-377: belts and levels.

const BELT_TOKENS: Record<RankColor, string> = {
  white: "--belt-white",
  grey: "--belt-grey",
  yellow: "--belt-yellow",
  orange: "--belt-orange",
  green: "--belt-green",
  blue: "--belt-blue",
  purple: "--belt-purple",
  brown: "--belt-brown",
  red: "--belt-red",
  black: "--belt-black",
  pink: "--belt-pink",
};

/** `var(--belt-blue)`; a level without a colour gets the muted panel. */
export function beltColor(color: RankColor | null | undefined): string {
  return color ? `var(${BELT_TOKENS[color]})` : "var(--panel-muted)";
}

/** 0–1 towards the next rank, from the counted requirements (classes and days). */
export function rankProgress(standing: RankStanding): number | null {
  const progress = standing.progress;
  if (!progress) return null;
  const parts = [progress.classes, progress.days].filter((count) => typeof count.needed === "number" && (count.needed as number) > 0);
  if (parts.length === 0) return null;
  const ratios = parts.map((count) => Math.min(1, (count.done ?? 0) / (count.needed as number)));
  return ratios.reduce((sum, ratio) => sum + ratio, 0) / ratios.length;
}

/** The ranks a coach may give next: a stripe on the current rank, or the next rank. Never down. */
export function promotionChoices(standing: RankStanding): { kind: "stripe" | "rank"; rank: Rank; stripes: number }[] {
  const choices: { kind: "stripe" | "rank"; rank: Rank; stripes: number }[] = [];
  const current = standing.current;
  if (current && current.stripes < current.rank.max_stripes) {
    choices.push({ kind: "stripe", rank: current.rank, stripes: current.stripes + 1 });
  }
  const next = standing.next ?? (!current ? standing.ladder.ranks[0] : null);
  if (next) choices.push({ kind: "rank", rank: next, stripes: 0 });
  return choices;
}
