/**
 * ADR-650: the canonical list of WOD formats a coach can write in a text
 * WOD («AMRAP 12», «E2MOM 20», «Tabata», «Για χρόνο, όριο 15'») and the
 * timer each one runs. It is built from the structured editor's six flows
 * and seventeen presets (ADR-270, `structured-plan/catalog.ts`), so a new
 * flow or preset there appears here, with the same names and agreed values.
 *
 * Each format says what the text editors do with it:
 * - `timer`: the free-text timer it sets (`FreeTextTimerPreset`), or `none`
 *   for the formats that are not a clock (sets, structures, rest, add-ons).
 *   These are still offered while typing, but never set a timer.
 * - `names`: what a coach writes, in every language Palee speaks
 *   (`locale-words.ts`), as written; `aliases` the same folded (lower case,
 *   no accents) plus the structured editor's search aliases.
 * - `write`: what a picked suggestion puts in the text (a name the parser
 *   reads back), `null` for the screen's translated label.
 * - `needsNumber`: the timer needs a number after the name («AMRAP 12»);
 *   the suggestion ends with a space for it, and the name alone sets nothing.
 */
import { FLOWS, FLOW_KEYS, PRESETS, type PresetKey } from "@/lib/structured-plan/catalog";
import type { PlanFlow } from "@/lib/structured-plan/types";

import { LOCALE_WORDS } from "./locale-words";

export type WodFormatTimer =
  | { kind: "none" }
  | { kind: "amrap"; durationSeconds: number | null }
  | { kind: "emom"; intervalSeconds: number | null }
  | { kind: "intervals"; format: "tabata" | "custom_hiit"; workSeconds: number | null; restSeconds: number | null; rounds: number | null }
  | { kind: "for_time" }
  | { kind: "death_by"; intervalSeconds: number };

export type WodFormatKey = PlanFlow | PresetKey;

export type WodFormat = {
  key: WodFormatKey;
  kind: "flow" | "preset";
  /** The flow the format runs on (a preset's flow). */
  flow: PlanFlow;
  /** i18n key of its name (`PlanCore.flow.*` / `PlanCore.preset.*`). */
  labelKey: string;
  /** Folded names (matching). */
  aliases: string[];
  /** Names a coach writes, as written (what a suggestion can put in the text). */
  names: string[];
  write: string | null;
  needsNumber: boolean;
  timer: WodFormatTimer;
};

/** Seconds of an agreed preset value ("20″", "3:00", "15" minutes); null when empty. */
export function presetSeconds(value: string | undefined, bare: "sec" | "min"): number | null {
  if (!value) return null;
  const text = value.trim();
  const clock = /^(\d+):(\d{2})$/.exec(text);
  if (clock) return Number(clock[1]) * 60 + Number(clock[2]);
  const amount = /^(\d+)\s*(″|"|''|s|sec)?\s*(′|'|m|min)?$/.exec(text);
  if (!amount) return null;
  if (amount[2]) return Number(amount[1]);
  if (amount[3]) return Number(amount[1]) * 60;
  return bare === "sec" ? Number(amount[1]) : Number(amount[1]) * 60;
}

const count = (value: string | undefined) => (value && /^\d+$/.test(value) ? Number(value) : null);

/**
 * What a coach writes besides the structured editor's names. Kept narrow on
 * purpose: a format is read only at the start of a line, and words that
 * also start exercise lines («Target», «Calories», «Rest») are left out.
 */
const TEXT_NAMES: Partial<Record<WodFormatKey, string[]>> = {
  amrap: ["AMRAP", "As many rounds as possible", "As many rounds", "As many reps", "Όσοι γύροι", "Όσους γύρους", "Όσο περισσότερους γύρους"],
  emom: ["EMOM", "E2MOM", "E3MOM", "E4MOM", "OTM", "Every minute on the minute", "Every minute", "Κάθε λεπτό", "Στο λεπτό"],
  for_time: ["For Time", "FT", "RFT", "Rounds for time", "Για χρόνο", "Γύροι για χρόνο", "Γύρους για χρόνο"],
  intervals: ["Intervals", "Interval", "HIIT", "Διαστήματα", "Διαλειμματική"],
  sets: ["Sets", "Strength", "Hypertrophy", "Σετ", "Δύναμη", "Υπερτροφία"],
  rest: ["Rest", "Ξεκούραση"],
  calorie_target: ["Calorie target", "Cal target", "Kcal target", "Στόχος θερμίδων"],
  death_by: ["Death by", "Deathby"],
  hrr: ["HRR", "Heart rate recovery", "Ανάκαμψη παλμών"],
  "21_15_9": ["21-15-9"],
  ladder: ["Ladder", "Pyramid", "Σκάλα", "Πυραμίδα"],
  even_odd: ["Even odd", "Odd even", "Alternating", "Εναλλάξ", "Μονά ζυγά"],
  superset: ["Superset", "Giant set"],
  drop_set: ["Drop set", "Dropset"],
  rest_pause: ["Rest-pause", "Rest pause", "Myo reps"],
  to_failure: ["To failure", "Μέχρι αποτυχία"],
};

/** Aliases of the structured catalog left out of text reading (they start ordinary lines). */
const NOT_IN_TEXT = new Set(["target", "στόχος", "kcal", "calories", "θερμίδες", "failure", "custom", "break", "διάλειμμα", "χωρίς χρόνο", "παλμοί", "θάνατος", "couplet"]);

/** What the suggestion inserts, where the name is the same in every language. */
const WRITE: Partial<Record<WodFormatKey, string>> = {
  amrap: "AMRAP",
  emom: "EMOM",
  for_time: "For Time",
  intervals: "Intervals",
  tabata: "Tabata",
  billat: "Billat",
  death_by: "Death by",
  complex_emom: "Complex EMOM",
  edt: "EDT",
  chipper: "Chipper",
  "21_15_9": "21-15-9",
  hrr: "HRR",
};

function fold(text: string) {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function flowTimer(flow: PlanFlow): WodFormatTimer {
  switch (flow) {
    case "amrap":
      return { kind: "amrap", durationSeconds: null };
    case "emom":
      return { kind: "emom", intervalSeconds: null };
    case "intervals":
      return { kind: "intervals", format: "custom_hiit", workSeconds: null, restSeconds: null, rounds: null };
    case "for_time":
      return { kind: "for_time" };
    default:
      return { kind: "none" };
  }
}

function presetTimer(key: PresetKey): WodFormatTimer {
  const preset = PRESETS.find((item) => item.key === key)!;
  const params = preset.params ?? {};
  if (preset.mods?.interrupt) return { kind: "none" };
  switch (key) {
    case "tabata":
      return { kind: "intervals", format: "tabata", workSeconds: presetSeconds(params.work, "sec"), restSeconds: presetSeconds(params.off, "sec"), rounds: count(params.rounds) };
    case "death_by":
      return { kind: "death_by", intervalSeconds: presetSeconds(params.every, "min") ?? 60 };
    default:
      break;
  }
  switch (preset.flow) {
    case "intervals":
      return { kind: "intervals", format: "custom_hiit", workSeconds: presetSeconds(params.work, "sec"), restSeconds: presetSeconds(params.off, "sec"), rounds: count(params.rounds) };
    case "amrap":
      return { kind: "amrap", durationSeconds: presetSeconds(params.dur, "min") };
    default:
      return flowTimer(preset.flow);
  }
}

function needsNumber(timer: WodFormatTimer) {
  switch (timer.kind) {
    case "amrap":
      return timer.durationSeconds === null;
    case "emom":
      return true;
    case "intervals":
      return timer.workSeconds === null || timer.rounds === null;
    default:
      return false;
  }
}

/**
 * The folded names a translated label gives: the whole label and each of its
 * names («Σκάλα / πυραμίδα», «Pulserholung (HRR)»), never a short word alone.
 */
export function labelNames(label: string): string[] {
  const parts = label.split(/\s*(?:\/|\(|\))\s*/u).map((part) => fold(part)).filter(Boolean);
  return [fold(label), ...parts.filter((part) => part.length >= 5 || (parts.length === 1 && part.length >= 2))];
}

/** What coaches write for a format in the other languages (ADR-650): their own words, then the labels. */
function localeNames(key: WodFormatKey): string[] {
  return Object.values(LOCALE_WORDS).flatMap((words) => {
    const label = words.labels[key];
    return [...(words.names[key] ?? []), ...(label ? label.split(/\s*(?:\/|\(|\))\s*/u).filter((part) => part.trim().length >= 2) : [])];
  });
}

function aliasesOf(key: WodFormatKey, base: string[]) {
  const labels = Object.values(LOCALE_WORDS).flatMap((words) => (words.labels[key] ? labelNames(words.labels[key]!) : []));
  const all = [...(TEXT_NAMES[key] ?? []), ...base.filter((alias) => !NOT_IN_TEXT.has(alias)), ...(Object.values(LOCALE_WORDS).flatMap((words) => words.names[key] ?? []))].map(fold);
  return [...new Set([...all, ...labels].filter(Boolean))];
}

function namesOf(key: WodFormatKey) {
  const seen = new Set<string>();
  return [...(TEXT_NAMES[key] ?? []), ...localeNames(key)].filter((name) => {
    const folded = fold(name);
    if (seen.has(folded)) return false;
    seen.add(folded);
    return true;
  });
}

function build(): WodFormat[] {
  const flows: WodFormat[] = FLOW_KEYS.map((key) => {
    const timer = flowTimer(key);
    return {
      key,
      kind: "flow",
      flow: key,
      labelKey: FLOWS[key].labelKey,
      aliases: aliasesOf(key, FLOWS[key].aliases),
      names: namesOf(key),
      write: WRITE[key] ?? null,
      needsNumber: needsNumber(timer),
      timer,
    };
  });
  const presets: WodFormat[] = PRESETS.map((preset) => {
    const timer = presetTimer(preset.key);
    return {
      key: preset.key,
      kind: "preset",
      flow: preset.flow,
      labelKey: preset.labelKey,
      aliases: aliasesOf(preset.key, preset.aliases),
      names: namesOf(preset.key),
      write: WRITE[preset.key] ?? null,
      needsNumber: needsNumber(timer),
      timer,
    };
  });
  return [...flows, ...presets];
}

/** Every format, flows first (in the structured editor's order), then the presets. */
export const WOD_FORMATS: WodFormat[] = build();

export const wodFormatByKey = (key: string): WodFormat | undefined => WOD_FORMATS.find((format) => format.key === key);

/** The formats that set a timer. */
export const TIMED_WOD_FORMATS = WOD_FORMATS.filter((format) => format.timer.kind !== "none");

export { fold as foldFormatText };
