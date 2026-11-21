/**
 * ADR-690: a WOD's types are a set of references. A reference is a Palee
 * kind key (a built-in kind of ADR-275 or one the Palee team added) or a
 * box's own type, `box:<id>`. Every reference has a family; there is no
 * main type. Mirrors `Palee.Workouts.Domain.WorkoutKinds`.
 */
import { WORKOUT_TYPE_FAMILIES, WORKOUT_TYPES, workoutTypeFamily, type WorkoutTypeFamily } from "@/lib/workout-types";

export type WorkoutKindAddition = { key: string; family: WorkoutTypeFamily; labels: Record<string, string> };

export type BoxWorkoutKind = {
  id: string;
  ref: string;
  label: string;
  family: WorkoutTypeFamily;
  status: "active" | "hidden" | "merged";
  merged_into: string | null;
};

export type WorkoutKindCatalogue = { additions: WorkoutKindAddition[]; box: BoxWorkoutKind[] };

export const EMPTY_WORKOUT_KIND_CATALOGUE: WorkoutKindCatalogue = { additions: [], box: [] };

const BOX_PREFIX = "box:";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export const WORKOUT_FAMILY_KEYS: readonly WorkoutTypeFamily[] = WORKOUT_TYPE_FAMILIES.map((group) => group.family);

export function boxKindRef(id: string) {
  return `${BOX_PREFIX}${id}`;
}

export function boxKindId(ref: string | null | undefined): string | null {
  if (!ref || !ref.startsWith(BOX_PREFIX)) return null;
  const id = ref.slice(BOX_PREFIX.length);
  return UUID.test(id) ? id : null;
}

export function isBoxKindRef(ref: string | null | undefined): boolean {
  return boxKindId(ref) !== null;
}

export function isWorkoutFamily(value: unknown): value is WorkoutTypeFamily {
  return typeof value === "string" && (WORKOUT_FAMILY_KEYS as readonly string[]).includes(value);
}

/** Merges catalogues: later entries win (a fresher read of the same box). */
export function mergeCatalogues(...catalogues: (WorkoutKindCatalogue | null | undefined)[]): WorkoutKindCatalogue {
  const additions = new Map<string, WorkoutKindAddition>();
  const box = new Map<string, BoxWorkoutKind>();
  for (const catalogue of catalogues) {
    for (const addition of catalogue?.additions ?? []) additions.set(addition.key, addition);
    for (const kind of catalogue?.box ?? []) box.set(kind.id, kind);
  }
  return { additions: [...additions.values()], box: [...box.values()] };
}

/** A merged box type reads as the type it was merged into. */
export function resolveMergedKind(ref: string, catalogue: WorkoutKindCatalogue, seen: string[] = []): string {
  const id = boxKindId(ref);
  if (!id || seen.includes(ref)) return ref;
  const kind = catalogue.box.find((entry) => entry.id === id);
  if (kind?.status === "merged" && kind.merged_into) return resolveMergedKind(kind.merged_into, catalogue, [...seen, ref]);
  return ref;
}

/** The family of a reference, or null when nothing names it yet. */
export function kindFamily(ref: string | null | undefined, catalogue: WorkoutKindCatalogue): WorkoutTypeFamily | null {
  if (!ref) return null;
  const builtin = workoutTypeFamily(ref);
  if (builtin) return builtin;
  const resolved = resolveMergedKind(ref, catalogue);
  if (resolved !== ref) return kindFamily(resolved, catalogue);
  const id = boxKindId(ref);
  if (id) return catalogue.box.find((kind) => kind.id === id)?.family ?? null;
  return catalogue.additions.find((addition) => addition.key === ref)?.family ?? null;
}

/** The families of `refs`, each once, in catalogue order. */
export function kindFamilies(refs: readonly string[], catalogue: WorkoutKindCatalogue): WorkoutTypeFamily[] {
  const chosen = new Set(refs.map((ref) => kindFamily(ref, catalogue)));
  return WORKOUT_FAMILY_KEYS.filter((family) => chosen.has(family));
}

/**
 * Orders references like the API: built-in kinds in catalogue order, then
 * additions by family and key, then box types by label. Order carries no
 * meaning; it only keeps lists stable.
 */
export function sortKindRefs(refs: readonly string[], catalogue: WorkoutKindCatalogue, label: (ref: string) => string): string[] {
  const builtinIndex = new Map<string, number>(WORKOUT_TYPES.map((type, index) => [type, index]));
  const rank = (ref: string): [number, number, string] => {
    if (builtinIndex.has(ref)) return [0, builtinIndex.get(ref)!, ""];
    if (isBoxKindRef(ref)) return [2, 0, foldKindLabel(label(ref))];
    const family = kindFamily(ref, catalogue);
    return [1, family ? WORKOUT_FAMILY_KEYS.indexOf(family) : 99, ref];
  };
  return [...new Set(refs)].sort((a, b) => {
    const [ga, ia, sa] = rank(a);
    const [gb, ib, sb] = rank(b);
    return ga - gb || ia - ib || sa.localeCompare(sb);
  });
}

/** Lowercase, no accents or tonos, final sigma, single spaces (as the API folds). */
export function foldKindLabel(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/ς/g, "σ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * A WOD's types as the API sends them: `types`, or an old record's single
 * `type`.
 */
export function workoutKindRefs(workout: { type?: string | null; types?: readonly string[] | null } | null | undefined): string[] {
  if (!workout) return [];
  if (workout.types && workout.types.length > 0) return [...workout.types];
  return workout.type ? [workout.type] : [];
}

/** The families of a WOD: the API's `families`, else worked out from its types. */
export function workoutKindFamilies(
  workout: { type?: string | null; types?: readonly string[] | null; families?: readonly string[] | null } | null | undefined,
  catalogue: WorkoutKindCatalogue = EMPTY_WORKOUT_KIND_CATALOGUE,
): WorkoutTypeFamily[] {
  const families = (workout?.families ?? []).filter(isWorkoutFamily);
  if (families.length > 0) return WORKOUT_FAMILY_KEYS.filter((family) => families.includes(family));
  return kindFamilies(workoutKindRefs(workout), catalogue);
}

/** References that need a lookup to be named (box types and kinds the Palee team added). */
export function unnamedKindRefs(refs: readonly string[]): string[] {
  return [...new Set(refs.filter((ref) => !workoutTypeFamily(ref)))].sort();
}
