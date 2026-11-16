/**
 * ADR-650: the formats offered while a coach types the start of a line in a
 * text WOD, in the same list as the exercise names (ADR-570) and above
 * them: first the coach's most used timers written out («AMRAP 12»,
 * «E2MOM 20»), then every format of the canonical list whose name starts
 * with what was typed. A name that needs a number ends with a space, so the
 * coach types it next.
 */
import { timerChipLabel, type FreeTextTimerPreset } from "@/lib/free-text-timer";

import { foldFormatText as fold, WOD_FORMATS, type WodFormatKey } from "./catalog";
import { lineStarts, readFormatLine, type FormatLabels } from "./parse";

export type FormatCompletion = {
  /** What goes in the text. */
  text: string;
  key: WodFormatKey | null;
  /** One of the coach's most used timers. */
  frequent: boolean;
  /** Character offset in the line where `text` replaces what was typed. */
  from: number;
};

/** The names the timer of a preset is written with in a text, whatever the screen's language. */
const TIMER_NAMES: Record<FreeTextTimerPreset["format"], string> = {
  untimed: "",
  amrap: "AMRAP",
  emom: "EMOM",
  for_time: "For Time",
  tabata: "Tabata",
  custom_hiit: "Intervals",
  death_by: "Death by",
};

/** How a timer is written in a text so that the parser reads it back: «AMRAP 12», «E2MOM 20», «For Time 15′». */
export function timerText(preset: FreeTextTimerPreset): string | null {
  if (preset.format === "untimed") return null;
  return timerChipLabel(preset, TIMER_NAMES[preset.format]);
}

const MAX_WORDS = 4;
const MAX_LENGTH = 32;

export function formatCompletions(
  lineBeforeCaret: string,
  options: { labels?: FormatLabels; frequent?: FreeTextTimerPreset[]; limit?: number } = {},
): FormatCompletion[] {
  const starts = lineStarts(lineBeforeCaret.toLowerCase());
  const from = starts[starts.length - 1] ?? 0;
  const typed = lineBeforeCaret.slice(from);
  const folded = fold(typed);
  if (folded.length < 2 || folded.length > MAX_LENGTH || !/\p{L}/u.test(folded)) return [];
  if (folded.split(" ").length > MAX_WORDS) return [];

  const out: FormatCompletion[] = [];
  const seen = new Set<string>();
  const add = (text: string, key: WodFormatKey | null, frequent: boolean) => {
    const name = fold(text);
    if (seen.has(name) || !name.startsWith(folded) || name === folded) return;
    seen.add(name);
    out.push({ text, key, frequent, from });
  };

  for (const preset of options.frequent ?? []) {
    const text = timerText(preset);
    if (text) add(text, readFormatLine(text)?.format.key ?? null, true);
  }

  // A line that already is a complete timer needs nothing more.
  const read = readFormatLine(typed, options.labels);
  if (read?.preset && out.length === 0) return [];

  for (const format of WOD_FORMATS) {
    const label = options.labels?.[format.key];
    const names = [format.write, ...format.names, label].filter((name): name is string => Boolean(name));
    const name = names.find((candidate) => fold(candidate).startsWith(folded));
    if (!name) continue;
    add(format.needsNumber ? `${name} ` : name, format.key, false);
  }
  return out.slice(0, options.limit ?? 4);
}
