import type { components } from "@/api/generated/schema";
import type { ProgrammeDay, ProgrammeInput, StaffProgramme } from "@/api/programmes";
import type { WorkoutRecord } from "@/api/workouts";
import {
  DAYS_PER_WEEK,
  MAX_WEEKS,
  MAX_WODS_PER_DAY,
  emptyWeeks,
  sameDays,
  sortDays,
  trimToWeeks,
} from "@/components/programmes/programme-grid";
import { WORKOUT_TYPE_FAMILIES, workoutTypeFamily, type WorkoutTypeFamily } from "@/lib/workout-types";

/**
 * The programme editor's pure side (board screens 1κ A and 1μ A, ADR-544):
 * the draft and what changed in it, the day and week operations the coach
 * does on `draft_days` (all client side: the API validates the saved
 * result), the selection maths of the desktop grid, «Λείπουν N πράγματα»
 * and «κύριος εξοπλισμός» (ADR-542).
 */

export type EquipmentKey = components["schemas"]["EquipmentKey"];
export type ReadinessItem = components["schemas"]["ProgrammeReadinessItem"];

/** The API's vocabulary order (ADR-542), which is also the order of the «Προσθήκη» list. */
export const EQUIPMENT_KEYS: readonly EquipmentKey[] = [
  "none",
  "barbell",
  "dumbbell",
  "kettlebell",
  "bench",
  "box",
  "pull_up_bar",
  "rings",
  "dip_bars",
  "climbing_rope",
  "ghd",
  "jump_rope",
  "wall_ball",
  "sled",
  "rower",
  "bike",
  "air_bike",
  "ski_erg",
  "pool",
  "band",
  "foam_roller",
];

/** At most this many keys the author adds (ADR-542 §5). */
export const MAX_ADDED_EQUIPMENT = 10;

// ── The draft ─────────────────────────────────────────────────────────────

export type Draft = {
  title: string;
  summary: string;
  level: StaffProgramme["level"];
  goal: StaffProgramme["goal"];
  weeks: number;
  days: ProgrammeDay[];
  /** Keys the author added to the derived equipment. */
  equipment: EquipmentKey[];
  /** Derived keys the author took away. */
  equipmentRemoved: EquipmentKey[];
};

export function draftOf(programme: StaffProgramme): Draft {
  return {
    title: programme.title ?? "",
    summary: programme.summary ?? "",
    level: programme.level,
    goal: programme.goal,
    weeks: Math.max(1, programme.draft_weeks || 1),
    days: programme.draft_days ?? [],
    equipment: programme.equipment ?? [],
    equipmentRemoved: programme.equipment_removed ?? [],
  };
}

function sameKeys(a: readonly string[], b: readonly string[]) {
  return a.length === b.length && a.every((key, index) => key === b[index]);
}

/** What to PATCH so the saved programme matches the draft; null when nothing changed. */
export function changesOf(saved: StaffProgramme, draft: Draft): ProgrammeInput | null {
  const body: ProgrammeInput = {};
  const title = draft.title.trim();
  if (title !== saved.title && title.length >= 2) body.title = title;
  if (draft.summary.trim() !== (saved.summary ?? "")) body.summary = draft.summary.trim() || null;
  if (draft.level && draft.level !== saved.level) body.level = draft.level;
  if (draft.goal && draft.goal !== saved.goal) body.goal = draft.goal;
  if (draft.weeks !== saved.draft_weeks) body.draft_weeks = draft.weeks;
  if (draft.weeks !== saved.draft_weeks || !sameDays(draft.days, saved.draft_days ?? [])) body.draft_days = draft.days;
  if (!sameKeys(draft.equipment, saved.equipment ?? [])) body.equipment = draft.equipment;
  if (!sameKeys(draft.equipmentRemoved, saved.equipment_removed ?? [])) body.equipment_removed = draft.equipmentRemoved;
  return Object.keys(body).length > 0 ? body : null;
}

// ── Days ──────────────────────────────────────────────────────────────────

export function weekOf(day: number) {
  return Math.floor(day / DAYS_PER_WEEK);
}

export function slotOf(day: number) {
  return day % DAYS_PER_WEEK;
}

/** The WODs of one day, in the order they were added. */
export function workoutsOn(days: ProgrammeDay[], day: number) {
  return days.filter((row) => row.day === day).map((row) => row.workout_id);
}

/** Training days (days with at least one WOD) in a week. */
export function trainingDays(days: ProgrammeDay[], week: number) {
  return new Set(days.filter((row) => weekOf(row.day) === week).map((row) => row.day)).size;
}

/** Sets a day's WODs (an empty list makes it a rest day). */
export function setDay(days: ProgrammeDay[], day: number, workoutIds: readonly string[]): ProgrammeDay[] {
  const unique = [...new Set(workoutIds)].slice(0, MAX_WODS_PER_DAY);
  return sortDays([...days.filter((row) => row.day !== day), ...unique.map((workout_id) => ({ day, workout_id }))]);
}

/** «Ξεκούραση» (Del): the days lose their WODs. */
export function restDays(days: ProgrammeDay[], targets: readonly number[]): ProgrammeDay[] {
  const cleared = new Set(targets);
  return days.filter((row) => !cleared.has(row.day));
}

/**
 * Puts one WOD on each target day, next to what is there. A day that has it
 * already is left alone; a full day (four WODs) is counted in `full`.
 */
export function placeWorkout(days: ProgrammeDay[], targets: readonly number[], workoutId: string) {
  let next = days;
  let placed = 0;
  let full = 0;
  for (const day of new Set(targets)) {
    const current = workoutsOn(next, day);
    if (current.includes(workoutId)) continue;
    if (current.length >= MAX_WODS_PER_DAY) {
      full += 1;
      continue;
    }
    next = sortDays([...next, { day, workout_id: workoutId }]);
    placed += 1;
  }
  return { days: next, placed, full };
}

/** ⌘/Ctrl V: each target day becomes a copy of the copied day. */
export function pasteDay(days: ProgrammeDay[], copied: readonly string[], targets: readonly number[]) {
  return [...new Set(targets)].reduce((next, day) => setDay(next, day, copied), days);
}

/**
 * Copies a week onto other weeks, filling only their empty days (ADR-544):
 * a day the coach already planned, or left for rest on purpose after
 * planning around it, is never overwritten. `filled` counts the days written.
 */
export function copyWeek(days: ProgrammeDay[], from: number, targets: readonly number[]) {
  const source = Array.from({ length: DAYS_PER_WEEK }, (_, slot) => workoutsOn(days, from * DAYS_PER_WEEK + slot));
  let next = days;
  let filled = 0;
  for (const week of new Set(targets)) {
    if (week === from) continue;
    source.forEach((workoutIds, slot) => {
      const day = week * DAYS_PER_WEEK + slot;
      if (workoutIds.length === 0 || workoutsOn(next, day).length > 0) return;
      next = setDay(next, day, workoutIds);
      filled += 1;
    });
  }
  return { days: next, filled };
}

/**
 * «Αντιγραφή στην επόμενη εβδομάδα»: the last week first gets a new week
 * after it (while there is room). `week` is the week to show afterwards.
 */
export function copyWeekToNext(days: ProgrammeDay[], weeks: number, from: number) {
  const target = from + 1;
  if (target >= weeks && weeks >= MAX_WEEKS) return { days, weeks, filled: 0, week: from };
  const nextWeeks = Math.max(weeks, target + 1);
  const copied = copyWeek(days, from, [target]);
  return { days: copied.days, weeks: nextWeeks, filled: copied.filled, week: target };
}

/** Deletes a week; the weeks after it move one week earlier. The last week stays. */
export function deleteWeek(days: ProgrammeDay[], weeks: number, week: number) {
  if (weeks <= 1 || week < 0 || week >= weeks) return { days, weeks };
  const next = days
    .filter((row) => weekOf(row.day) !== week)
    .map((row) => (weekOf(row.day) > week ? { ...row, day: row.day - DAYS_PER_WEEK } : row));
  return { days: sortDays(next), weeks: weeks - 1 };
}

/** «Αλλαγή σειράς»: moves a week to another position, the others keeping their order. */
export function moveWeek(days: ProgrammeDay[], weeks: number, from: number, to: number) {
  if (from === to || from < 0 || to < 0 || from >= weeks || to >= weeks) return days;
  const order = Array.from({ length: weeks }, (_, week) => week);
  order.splice(from, 1);
  order.splice(to, 0, from);
  const position = new Map(order.map((week, index) => [week, index]));
  return sortDays(days.map((row) => ({ ...row, day: (position.get(weekOf(row.day)) ?? 0) * DAYS_PER_WEEK + slotOf(row.day) })));
}

export function addWeek(weeks: number) {
  return Math.min(MAX_WEEKS, weeks + 1);
}

export { trimToWeeks };

// ── Desktop grid selection ────────────────────────────────────────────────

/** Shift + click: every day from the anchor to the target, in reading order. */
export function dayRange(anchor: number, target: number) {
  const [from, to] = anchor <= target ? [anchor, target] : [target, anchor];
  return Array.from({ length: to - from + 1 }, (_, index) => from + index);
}

/** Where an arrow key moves the focused day in a grid of `weeks` rows of seven days. */
export function moveCursor(day: number, key: string, weeks: number) {
  const last = weeks * DAYS_PER_WEEK - 1;
  const step: Record<string, number> = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -DAYS_PER_WEEK, ArrowDown: DAYS_PER_WEEK };
  if (key === "Home") return weekOf(day) * DAYS_PER_WEEK;
  if (key === "End") return weekOf(day) * DAYS_PER_WEEK + DAYS_PER_WEEK - 1;
  const next = day + (step[key] ?? 0);
  return next < 0 || next > last ? day : next;
}

// ── «Λείπουν N πράγματα» (ADR-544) ─────────────────────────────────────────

export type ReadinessTarget = { tab: "weeks"; week: number } | { tab: "details"; field: "title" | "summary" };

/**
 * What the draft still lacks, live (the API's `readiness` mirrored, so the
 * list follows each change before the autosave). The price is left out: the
 * «Δημοσίευση…» dialog asks for it and says so under its field.
 */
export function liveReadiness(draft: Pick<Draft, "title" | "summary" | "weeks" | "days">): ReadinessItem[] {
  const items: ReadinessItem[] = [];
  if (draft.title.trim() === "") items.push({ key: "title", blocking: true, weeks: [] });
  if (draft.days.length === 0) items.push({ key: "days", blocking: true, weeks: [] });
  else {
    const empty = emptyWeeks(draft.weeks, draft.days);
    if (empty.length > 0) items.push({ key: "empty_weeks", blocking: false, weeks: empty });
  }
  if (draft.summary.trim() === "") items.push({ key: "summary", blocking: false, weeks: [] });
  return items;
}

export function readinessTarget(item: ReadinessItem): ReadinessTarget | null {
  switch (item.key) {
    case "title":
    case "summary":
      return { tab: "details", field: item.key };
    case "days":
      return { tab: "weeks", week: 0 };
    case "empty_weeks":
      return { tab: "weeks", week: Math.max(0, (item.weeks[0] ?? 1) - 1) };
    default:
      return null;
  }
}

// ── «Κύριος εξοπλισμός» (ADR-542) ─────────────────────────────────────────

/** Shown: the author's keys first, then the derived ones not taken away (the API's `main_equipment`). */
export function shownEquipment(derived: readonly EquipmentKey[], added: readonly EquipmentKey[], removed: readonly EquipmentKey[]) {
  const out = [...added];
  for (const key of derived) if (!removed.includes(key) && !out.includes(key)) out.push(key);
  return out;
}

/** Takes a key away: an added key is simply dropped, a derived one is remembered as removed. */
export function removeEquipment(derived: readonly EquipmentKey[], added: EquipmentKey[], removed: EquipmentKey[], key: EquipmentKey) {
  const nextAdded = added.filter((entry) => entry !== key);
  const nextRemoved = derived.includes(key) && !removed.includes(key) ? [...removed, key] : removed;
  return { equipment: nextAdded, equipmentRemoved: nextRemoved };
}

/** Adds a key: a removed derived key comes back, any other is added by the author. */
export function addEquipment(derived: readonly EquipmentKey[], added: EquipmentKey[], removed: EquipmentKey[], key: EquipmentKey) {
  if (removed.includes(key)) return { equipment: added, equipmentRemoved: removed.filter((entry) => entry !== key) };
  if (added.includes(key) || derived.includes(key) || added.length >= MAX_ADDED_EQUIPMENT) return { equipment: added, equipmentRemoved: removed };
  return { equipment: [...added, key], equipmentRemoved: removed };
}

/** The keys «Προσθήκη» offers: every vocabulary key not shown. */
export function addableEquipment(derived: readonly EquipmentKey[], added: readonly EquipmentKey[], removed: readonly EquipmentKey[]) {
  const shown = new Set(shownEquipment(derived, added, removed));
  const roomForNew = added.length < MAX_ADDED_EQUIPMENT;
  return EQUIPMENT_KEYS.filter((key) => !shown.has(key) && (removed.includes(key) || roomForNew));
}

// ── The WOD library ───────────────────────────────────────────────────────

export type LibraryWod = {
  id: string;
  title: string;
  type: string;
  family: WorkoutTypeFamily | null;
  icon: string | null;
  /** Whole minutes, only when the WOD states its length. */
  minutes: number | null;
};

/** The published WODs, ready for the library and the grid. */
export function libraryOf(workouts: readonly WorkoutRecord[] | null | undefined): LibraryWod[] {
  if (!Array.isArray(workouts)) return [];
  return workouts
    .filter((workout) => workout?.id && workout.status === "published")
    .map((workout) => {
      const seconds = (workout as WorkoutRecord & { estimated_duration_seconds?: number | null }).estimated_duration_seconds;
      return {
        id: workout.id,
        title: workout.title,
        type: workout.type,
        family: workoutTypeFamily(workout.type),
        icon: workout.icon ?? null,
        minutes: typeof seconds === "number" && seconds > 0 ? Math.round(seconds / 60) : null,
      };
    });
}

/** The families present in the library, in catalogue order (the filter chips). */
export function libraryFamilies(items: readonly LibraryWod[]): WorkoutTypeFamily[] {
  const present = new Set(items.map((item) => item.family));
  return WORKOUT_TYPE_FAMILIES.map((group) => group.family).filter((family) => present.has(family));
}

export function filterLibrary(items: readonly LibraryWod[], query: string, family: WorkoutTypeFamily | null) {
  const needle = query.trim().toLocaleLowerCase();
  return items.filter((item) => (!family || item.family === family) && (!needle || item.title.toLocaleLowerCase().includes(needle)));
}

/** «Πρόσφατα»: the WODs already in this programme, the latest day first. */
export function recentWorkouts(days: readonly ProgrammeDay[], limit = 6) {
  const seen: string[] = [];
  for (const row of [...days].sort((a, b) => b.day - a.day)) {
    if (!seen.includes(row.workout_id)) seen.push(row.workout_id);
    if (seen.length >= limit) break;
  }
  return seen;
}
