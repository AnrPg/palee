/**
 * ADR-650: where a text WOD's timer comes from. While it follows the text
 * (`from: "text"`) the timer is the first one the text asks for (or the
 * one picked with «Το επόμενο»), and none when the text asks for none. Once
 * the coach changes it by hand (`from: "hand"`) the text no longer changes
 * it, until «Από το κείμενο» gives it back to the text.
 *
 * Nothing about the source is stored: a saved draft is read back as
 * following the text when its timer is the one its text asks for, so
 * drafts saved before this feature keep the timer they had.
 */
import { sameTimerPreset, type FreeTextTimerPreset } from "@/lib/free-text-timer";

import { findTextTimers, type TextTimerFinding, type TextTimers } from "./parse";

export type TimerFrom = { from: "text" | "hand"; pick: number };

export const FOLLOW_TEXT: TimerFrom = { from: "text", pick: 0 };

/** The timer of the text a source points at: the `pick`-th found, wrapping around. */
export function pickedTextTimer(found: TextTimers, pick: number): TextTimerFinding | null {
  const count = found.timers.length;
  return count ? found.timers[((pick % count) + count) % count]! : null;
}

/** The timer a WOD runs: the text's while it follows the text, else the coach's own. */
export function effectiveTimer<Empty extends FreeTextTimerPreset | null>(
  found: TextTimers,
  source: TimerFrom,
  hand: FreeTextTimerPreset | Empty,
  empty: Empty,
): FreeTextTimerPreset | Empty {
  if (source.from === "hand") return hand;
  return pickedTextTimer(found, source.pick)?.preset ?? empty;
}

/**
 * The source of a saved timer. It follows the text when it is one of the
 * text's timers, or when nothing is set and the text asks for nothing;
 * otherwise it is the coach's own (a draft from before ADR-650 included).
 */
export function loadTimerFrom(text: string, stored: FreeTextTimerPreset | null, emptyFormat: "untimed" | null): TimerFrom {
  const found = findTextTimers(text);
  const unset = stored === null || (emptyFormat !== null && stored.format === emptyFormat);
  if (unset) return found.timers.length === 0 ? FOLLOW_TEXT : { from: "hand", pick: 0 };
  const index = found.timers.findIndex((item) => sameTimerPreset(item.preset, stored));
  return index >= 0 ? { from: "text", pick: index } : { from: "hand", pick: 0 };
}
