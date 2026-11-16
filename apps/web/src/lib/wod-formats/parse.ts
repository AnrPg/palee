/**
 * ADR-650: reads the timer a text WOD asks for, line by line, the way a coach
 * writes it on the whiteboard («AMRAP 12», «12' AMRAP», «E2MOM 20»,
 * «Every 90s x 8», «Κάθε 3' x 5», «Tabata x 6», «40/20 x 8», «For time,
 * cap 15», «5 RFT», «21-15-9», «Death by»). A format is read only where a
 * line starts with it (after a bullet, a number or a short «Part B:» label),
 * so exercise lines never set a timer. A name without the number its timer
 * needs («AMRAP» alone) is `incomplete`: it sets nothing.
 *
 * Bare numbers read as coaches mean them: minutes after AMRAP, EMOM and a
 * time cap; seconds in a work/rest pair («40/20»).
 */
import { canonicalTimerPreset, type FreeTextTimerPreset } from "@/lib/free-text-timer";

import { foldFormatText as fold, labelNames, WOD_FORMATS, type WodFormat, type WodFormatKey } from "./catalog";
import { LOCALE_WORDS, type LocaleWords } from "./locale-words";

export type FormatLabels = Partial<Record<WodFormatKey, string>>;

export type FormatLineRead = {
  format: WodFormat;
  /** The timer the line sets; null for a format that is not a clock or an incomplete one. */
  preset: FreeTextTimerPreset | null;
  incomplete: boolean;
};

export type TextTimerFinding = { line: number; key: WodFormatKey; preset: FreeTextTimerPreset };

export type TextTimers = {
  /** The timers found, in the order of the text. */
  timers: TextTimerFinding[];
  /** Formats written without the number their timer needs, in the order of the text. */
  incomplete: { line: number; key: WodFormatKey }[];
};

/** The words of every language Palee speaks (ADR-650), folded, longest first, as a regex alternation. */
function alternation(...lists: string[][]) {
  const words = [...new Set(lists.flat().map(fold).filter(Boolean))].sort((a, b) => b.length - a.length);
  return words.map((word) => word.replace(/[.*+?^${}()|[\]\\/]/gu, "\\$&").replace(/ /gu, "\\s*")).join("|");
}
const all = (pick: (words: LocaleWords) => string[]) => Object.values(LOCALE_WORDS).map(pick);

const SECOND_UNITS = ["″", '"', "''", "s", "sec", "secs", "second", "seconds", "δ", "δευτ", "δευτερολεπτα", ...all((w) => w.seconds).flat()];
const MINUTE_UNITS = ["′", "'", "m", "min", "mins", "minute", "minutes", "λ", "λεπτ", "λεπτα", "λεπτο", ...all((w) => w.minutes).flat()];
const SECOND_SET = new Set(SECOND_UNITS.map(fold));
const UNIT = String.raw`(${alternation(SECOND_UNITS, MINUTE_UNITS)})?`;
const TIME = String.raw`(\d{1,3})(?::(\d{2}))?\s*${UNIT}(?![\p{L}\d])`;
const ROUNDS = alternation(["rounds", "round", "rds", "rd", "sets", "set", "γυροι", "γυρους", "γυρος", "γυρο", "σετ"], ...all((w) => w.rounds));
const EVERY = alternation(["every", "καθε"], ...all((w) => w.every));
const CAP = alternation(["time cap", "cap", "tc", "χρονικο οριο", "οριο"], ...all((w) => w.cap));
const DURING = alternation(["in", "σε", "για", "for"], ...all((w) => w.during));
const WORK = alternation(["on", "work", "δουλεια", "ασκηση"], ...all((w) => w.work));
const OFF = alternation(["off", "rest", "ξεκουραση", "διαλειμμα"], ...all((w) => w.off));
/** «x», «×» and the Cyrillic «х». */
const TIMES = "[x×х]";

/** Seconds of a time token; a bare number takes `bare`. */
function seconds(amount: string, clock: string | undefined, unit: string | undefined, bare: "sec" | "min") {
  if (clock !== undefined) return Number(amount) * 60 + Number(clock);
  const n = Number(amount);
  if (!unit) return bare === "sec" ? n : n * 60;
  return SECOND_SET.has(unit.replace(/\s+/gu, " ")) ? n : n * 60;
}

const LEADING_TIME = new RegExp(String.raw`^[\s:,.\-–(]*(?:(?:${DURING})\s*)?${TIME}`, "u");
const leadingTime = (rest: string, bare: "sec" | "min") => {
  const m = LEADING_TIME.exec(rest);
  return m ? seconds(m[1]!, m[2], m[3], bare) : null;
};

const ONLY_TIME = new RegExp(String.raw`^[\s:,.\-–(]*${TIME}[\s).]*$`, "u");
const onlyTime = (rest: string, bare: "sec" | "min") => {
  const m = ONLY_TIME.exec(rest);
  return m ? seconds(m[1]!, m[2], m[3], bare) : null;
};

/** «x 8», «× 8», «8 rounds», «8 γύροι», «8 Runden», «for 8 rounds». */
const TIMES_COUNT = new RegExp(String.raw`(?:^|[\s(,])${TIMES}\s*(\d{1,3})(?!\d)`, "u");
const NAMED_COUNT = new RegExp(String.raw`(\d{1,3})\s*(?:${ROUNDS})(?![\p{L}])`, "u");
const roundsIn = (rest: string) => {
  const times = TIMES_COUNT.exec(rest);
  if (times) return Number(times[1]);
  const named = NAMED_COUNT.exec(rest);
  return named ? Number(named[1]) : null;
};

/** A time cap anywhere on the line: «cap 15», «TC 15'», «time cap 12:00», «όριο 15», «Zeitlimit 15». */
const CAP_TIME = new RegExp(String.raw`(?:${CAP})\s*[:=]?\s*${TIME}`, "u");
const capIn = (line: string) => {
  const m = CAP_TIME.exec(line);
  return m ? seconds(m[1]!, m[2], m[3], "min") : null;
};

/** «40/20», «40 on 20 off», «30s on / 30s off», «1:00/1:00», «40 Belastung 20 Pause». */
const WORK_REST = new RegExp(String.raw`^[\s:,.\-–(]*${TIME}\s*(?:${WORK})?\s*(?:\/|:|\s)\s*${TIME}\s*(?:${OFF})?`, "u");
const workRestIn = (rest: string) => {
  const m = WORK_REST.exec(rest);
  if (!m) return null;
  return { work: seconds(m[1]!, m[2], m[3], "sec"), rest: seconds(m[4]!, m[5], m[6], "sec"), end: m[0].length };
};

type Matcher = { format: WodFormat; alias: string };

function matchersFor(labels: FormatLabels | undefined): Matcher[] {
  const out: Matcher[] = [];
  for (const format of WOD_FORMATS) {
    const names = new Set(format.aliases);
    const label = labels?.[format.key];
    if (label) for (const name of labelNames(label)) names.add(name);
    for (const alias of names) out.push({ format, alias });
  }
  // Longest first: «complex emom» before «emom», «rounds for time» before «rft».
  return out.sort((a, b) => b.alias.length - a.alias.length);
}

const cache = new WeakMap<object, Matcher[]>();
const NO_LABELS = {};
function matchers(labels: FormatLabels | undefined) {
  const key = labels ?? NO_LABELS;
  let found = cache.get(key);
  if (!found) {
    found = matchersFor(labels);
    cache.set(key, found);
  }
  return found;
}

const byKey = (key: WodFormatKey) => WOD_FORMATS.find((format) => format.key === key)!;

/** Where the words of a line start: past a bullet, a number («1.», «A)») and a short label («Part B:»). */
export function lineStarts(line: string): number[] {
  const bullet = /^[\s\-–—•*·>#]*(?:\(?[a-zα-ω0-9]{1,2}[).]\s+)?/u.exec(line)?.[0].length ?? 0;
  const out = [bullet];
  const label = /^([^:\n]{1,30}?)(?::|\s[-–—]\s)\s*/u.exec(line.slice(bullet));
  if (label && label[1]!.trim().split(/\s+/u).length <= 3) out.push(bullet + label[0].length);
  return out;
}

function presetFor(format: WodFormat, prefix: string, rest: string, line: string, everyFromName: number | null): FormatLineRead {
  const timer = format.timer;
  const done = (preset: FreeTextTimerPreset | null) => ({ format, preset: preset ? canonicalTimerPreset(preset) : null, incomplete: false });
  const incomplete = { format, preset: null, incomplete: true };
  switch (timer.kind) {
    case "none":
      return done(null);
    case "amrap": {
      const duration = leadingTime(rest, "min") ?? onlyTime(prefix, "min") ?? timer.durationSeconds;
      return duration ? done({ format: "amrap", duration_seconds: duration }) : incomplete;
    }
    case "emom": {
      const body = rest.replace(/^[\s:,.\-–]*(?:emom|otm)(?![\p{L}])/u, "");
      const every = everyFromName ?? timer.intervalSeconds ?? 60;
      // «EMOM x 10» counts rounds; «EMOM 10», «E2MOM 20», «20' EMOM» give the whole time.
      const times = new RegExp(String.raw`^[\s:,]*${TIMES}\s*(\d{1,3})(?!\d)`, "u").exec(body);
      if (times) return done({ format: "emom", interval_seconds: every, rounds: Number(times[1]) });
      // «EMOM 8 × 1:30»: rounds × interval (how a timer chip writes it).
      const grid = new RegExp(String.raw`^[\s:,]*(\d{1,3})\s*${TIMES}\s*${TIME}`, "u").exec(body);
      if (grid && everyFromName === null) {
        return done({ format: "emom", interval_seconds: seconds(grid[2]!, grid[3], grid[4], "min"), rounds: Number(grid[1]) });
      }
      const total = leadingTime(body, "min") ?? onlyTime(prefix, "min");
      if (total) return total % every === 0 ? done({ format: "emom", interval_seconds: every, rounds: total / every }) : incomplete;
      const rounds = roundsIn(body);
      return rounds ? done({ format: "emom", interval_seconds: every, rounds }) : incomplete;
    }
    case "intervals": {
      const pair = workRestIn(rest);
      const work = pair?.work ?? timer.workSeconds;
      const restSeconds = pair ? pair.rest : timer.restSeconds;
      const rounds = roundsIn(pair ? rest.slice(pair.end) : rest) ?? timer.rounds;
      if (!work || !rounds) return incomplete;
      const tabata = timer.format === "tabata" || (work === 20 && restSeconds === 10);
      return done({ format: tabata ? "tabata" : "custom_hiit", work_seconds: work, rest_seconds: restSeconds, rounds });
    }
    case "for_time": {
      const cap = capIn(line) ?? onlyTime(rest, "min");
      return done(cap ? { format: "for_time", duration_seconds: cap } : { format: "for_time" });
    }
    case "death_by": {
      const said = new RegExp(String.raw`(?:${EVERY})\s*${TIME}`, "u").exec(rest);
      const every = said ? seconds(said[1]!, said[2], said[3], "min") : onlyTime(rest, "min");
      return done({ format: "death_by", interval_seconds: every ?? timer.intervalSeconds });
    }
  }
}

/** The format a line starts with, its alias, and what follows it. */
function readAt(folded: string, at: number, labels: FormatLabels | undefined): FormatLineRead | null {
  const text = folded.slice(at);

  // «E2MOM 20», «E3MOM x 5», «E90S x 8».
  const everyName = /^e(\d{1,2})mom(?![\p{L}])/u.exec(text) ?? /^e(\d{2,3})s(?:ec)?(?![\p{L}])/u.exec(text);
  if (everyName) {
    const every = text.startsWith(`e${everyName[1]}mom`) ? Number(everyName[1]) * 60 : Number(everyName[1]);
    return presetFor(byKey("emom"), "", text.slice(everyName[0].length), folded, every);
  }

  // «Every 2' x 6», «Κάθε 3' x 5», «Every 1:30 for 12'».
  const every = new RegExp(String.raw`^(?:${EVERY})\s*${TIME}`, "u").exec(text);
  if (every) {
    const interval = seconds(every[1]!, every[2], every[3], "min");
    return presetFor(byKey("emom"), "", text.slice(every[0].length), folded, interval);
  }

  // «40/20 x 8», «30 on 30 off x 10».
  const pair = workRestIn(text);
  if (pair && pair.end > 0 && roundsIn(text.slice(pair.end)) && /^\s*\d/u.test(text)) {
    return presetFor(byKey("intervals"), "", text, folded, null);
  }

  // A name, possibly after a time or a count: «12' AMRAP», «5 RFT», «3 rounds for time».
  const lead = new RegExp(String.raw`^(?:${TIME}|(\d{1,3})\s*(?:${ROUNDS}))\s*`, "u").exec(text)?.[0] ?? "";
  // The name first at the start («21-15-9»), then after a time or a count.
  for (const prefix of lead ? ["", lead] : [""]) {
    const words = text.slice(prefix.length);
    for (const { format, alias } of matchers(labels)) {
      if (!words.startsWith(alias)) continue;
      const next = words[alias.length];
      if (next !== undefined && /[\p{L}\d]/u.test(next)) continue;
      // A number before the name is a count of rounds or the minutes of the clock.
      if (prefix && !["amrap", "for_time", "emom"].includes(format.timer.kind)) continue;
      return presetFor(format, prefix, words.slice(alias.length), folded, null);
    }
  }
  return null;
}

/** What one line of a text WOD asks for, or null when it does not start with a format. */
export function readFormatLine(line: string, labels?: FormatLabels): FormatLineRead | null {
  const folded = fold(line).replace(/(\d)\s*[-–]\s*(?=\d)/gu, "$1-");
  if (!folded) return null;
  for (const at of lineStarts(folded)) {
    const read = readAt(folded, at, labels);
    if (read) return read;
  }
  return null;
}

/** Every timer a text asks for, and the formats missing their number. */
export function findTextTimers(text: string, labels?: FormatLabels): TextTimers {
  const timers: TextTimerFinding[] = [];
  const incomplete: TextTimers["incomplete"] = [];
  text.split("\n").forEach((line, index) => {
    if (line.length > 160) return;
    const read = readFormatLine(line, labels);
    if (!read) return;
    if (read.preset) timers.push({ line: index, key: read.format.key, preset: read.preset });
    else if (read.incomplete) incomplete.push({ line: index, key: read.format.key });
  });
  return { timers, incomplete };
}
