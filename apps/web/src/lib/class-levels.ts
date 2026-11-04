// ADR-460: class type levels. Dependency-free on purpose: next.config.ts loads
// member-routes → around, which reads CLASS_LEVELS, so this file must import
// nothing (no "@/" aliases resolve there).

/** The levels a class type can suit, in display order. None chosen means «Όλα τα επίπεδα». */
export const CLASS_LEVELS = ["beginner", "intermediate", "advanced"] as const;
export type ClassLevel = (typeof CLASS_LEVELS)[number];

/** Whether a class type with `classLevels` suits one of the `wanted` levels (none wanted, or none set: yes). */
export function suitsLevels(classLevels: readonly string[] | null | undefined, wanted: readonly string[]) {
  if (wanted.length === 0 || !classLevels || classLevels.length === 0) return true;
  return classLevels.some((level) => wanted.includes(level));
}

/** The known levels of a class type, once each and in display order; unknown values are dropped. */
export function classLevelsOf(classLevels: readonly string[] | null | undefined): ClassLevel[] {
  return CLASS_LEVELS.filter((level) => classLevels?.includes(level));
}
