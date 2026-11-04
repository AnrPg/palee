import type { TimerSegment } from "@/api/executions";

/**
 * ADR-549 (Παραίτηση), the device's half: which time-set sections the
 * athlete stopped before their clock ran out, so the finish wizard can ask
 * «Σταμάτησες πριν τελειώσει ο χρόνος;». Mirrors the server's
 * `Retirement.time_set_sections/1`: every work segment of the section has a
 * fixed length (countdowns, a set number of windows) and it is not scored
 * by time. The server decides the verdict; this only chooses when to ask.
 */

/** Clocks commit whole milliseconds and the last tick may round (the server's tolerance). */
export const CLOCK_TOLERANCE_MS = 1_000;

export type StoppedEarlySection = {
  section_id: string;
  section_name: string;
  ran_ms: number;
  planned_ms: number;
};

export type RetirementAnswer = "gave_up" | "chose_shorter";

function fixedMs(segment: TimerSegment): number | null {
  const seconds = segment.duration_seconds;
  if (segment.kind === "countdown") return typeof seconds === "number" && seconds > 0 ? seconds * 1000 : null;
  if (segment.kind !== "interval_cycle") return null;
  const windows = segment.total_rounds;
  const raw = segment.timer_config?.interval_pattern_seconds;
  const pattern =
    Array.isArray(raw) && raw.length > 0 && raw.every((n) => typeof n === "number" && n > 0)
      ? (raw as number[])
      : typeof seconds === "number" && seconds > 0
        ? [seconds]
        : [];
  if (typeof windows !== "number" || windows <= 0 || pattern.length === 0) return null;
  let total = 0;
  for (let i = 0; i < windows; i++) total += pattern[i % pattern.length];
  return total * 1000;
}

/** Time-set sections of a sequence, in order: section id => its length (ms) and name. */
export function timeSetSections(segments: TimerSegment[]): Map<string, { planned_ms: number; section_name: string }> {
  const groups = new Map<string, TimerSegment[]>();
  for (const segment of segments) {
    if (segment.between_sections) continue;
    groups.set(segment.section_id, [...(groups.get(segment.section_id) ?? []), segment]);
  }
  const result = new Map<string, { planned_ms: number; section_name: string }>();
  for (const [id, group] of groups) {
    const lengths = group.map(fixedMs);
    const work = group.some((segment) => (segment.phase ?? "work") === "work");
    const byTime = group.some((segment) => segment.score_config?.type === "time");
    if (!work || byTime || lengths.some((ms) => ms === null)) continue;
    const planned = (lengths as number[]).reduce((a, b) => a + b, 0);
    if (planned > 0) result.set(id, { planned_ms: planned, section_name: group[0].section_name });
  }
  return result;
}

/**
 * The time-set sections that ran less than their clock (the clock as run,
 * after the athlete's own «+/−30 s»): the sections to ask about.
 */
export function stoppedEarlySections(
  segments: TimerSegment[],
  sectionElapsedMs: Record<string, number>,
): StoppedEarlySection[] {
  return [...timeSetSections(segments)].flatMap(([id, section]) => {
    const ran = Math.max(0, Math.round(sectionElapsedMs[id] ?? 0));
    return ran < section.planned_ms - CLOCK_TOLERANCE_MS
      ? [{ section_id: id, section_name: section.section_name, ran_ms: ran, planned_ms: section.planned_ms }]
      : [];
  });
}
