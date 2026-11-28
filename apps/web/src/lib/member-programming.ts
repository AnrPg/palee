/**
 * ADR-125 personalized member programming: pure UI rules shared by the staff
 * programming dialog, the class card and the member's workout list.
 */

import type { MemberProgrammingMode } from "@/api/admin-users";

/** The order the staff dialog offers member modes in (safest first). */
export const MEMBER_PROGRAMMING_MODES: readonly MemberProgrammingMode[] = [
  "class_variant",
  "personal",
  "class_workout",
];

/** Modes that attach to a class the member booked on the selected day. */
export function modeRequiresBookedClass(mode: MemberProgrammingMode): boolean {
  return mode === "class_variant" || mode === "class_workout";
}

/**
 * Modes that need the member's package to include personal programming.
 * ADR-785: a class variant is part of the class, so only `personal` does.
 */
export function modeRequiresProgrammingEntitlement(mode: MemberProgrammingMode): boolean {
  return mode === "personal";
}

/**
 * ADR-805: whether a mode is closed for this person. A member's own WOD for a
 * day (`personal`) is open when their package lets them book classes (it
 * uses one class visit) or includes online programming / personal training.
 * Everything is closed for an athlete without the grant.
 */
export function modeClosed(
  mode: MemberProgrammingMode | null,
  input: { isMember: boolean; programmingAllowed: boolean; classVisits: boolean },
): boolean {
  if (input.programmingAllowed) return false;
  if (!input.isMember || mode === null) return true;
  return modeRequiresProgrammingEntitlement(mode) && !input.classVisits;
}

type OfferableSlot = { id: string; scheduled_at: string; duration_minutes?: number | null; cancelled_at?: string | null };

/** ADR-785 (α): a class takes a variant from now until it ends, never once cancelled. */
export function classTakesVariant(slot: OfferableSlot, now: number): boolean {
  if (slot.cancelled_at) return false;
  const start = Date.parse(slot.scheduled_at);
  if (Number.isNaN(start)) return false;
  return start + (slot.duration_minutes ?? 60) * 60_000 > now;
}

/**
 * ADR-785 (1A): the classes of a day a member's variant can go to from their
 * profile, beyond those they booked: still open (see `classTakesVariant`)
 * and not booked by them, in time order. Booking is not needed: they get the
 * variant and a notice with «Κράτηση».
 */
export function offerableClasses<T extends OfferableSlot>(slots: readonly T[], bookedIds: ReadonlySet<string>, now: number): T[] {
  return slots
    .filter((slot) => !bookedIds.has(slot.id) && classTakesVariant(slot, now))
    .sort((a, b) => a.scheduled_at.localeCompare(b.scheduled_at));
}

/** Translation key for the staff-dialog success message of a programming run. */
export function programmingSuccessKey(
  role: "member" | "athlete" | "admin",
  mode: MemberProgrammingMode,
): string {
  if (role !== "member") return "featurePersonalWodAssigned";
  if (mode === "class_variant") return "memberProgrammingVariantCreated";
  if (mode === "personal") return "memberProgrammingPersonalAssigned";
  return "featureClassWodAttached";
}

/**
 * Where the programmed workout comes from, offered as the dialog's second
 * step. "adapt_class" and "new" open the workout editor first; the others
 * assign straight away.
 */
export type ProgrammingSource = "adapt_class" | "class_as_is" | "library" | "new";

/** The workout sources that fit a role and mode, the recommended one first. */
export function programmingSources(
  role: "member" | "athlete" | "admin",
  mode: MemberProgrammingMode,
): readonly ProgrammingSource[] {
  if (role === "member" && mode === "class_variant") return ["adapt_class", "class_as_is", "library", "new"];
  return ["library", "new"];
}

/** Sources that build on the booked class's own workout. */
export function sourceUsesClassWorkout(source: ProgrammingSource): boolean {
  return source === "adapt_class" || source === "class_as_is";
}

/** Sources whose primary action opens the editor (assigned when published). */
export function sourceOpensEditor(source: ProgrammingSource): boolean {
  return source === "adapt_class" || source === "new";
}

/** Replacing the class's workout already reaches everyone booked in it. */
export function canProgramMorePeople(role: "member" | "athlete" | "admin", mode: MemberProgrammingMode): boolean {
  return !(role === "member" && mode === "class_workout");
}

/**
 * The first thing still missing before the dialog's one primary action can
 * run, as a translation key, or null when it is ready. The dialog shows it
 * next to the disabled button so staff always know why it waits.
 */
export function programmingBlocker(input: {
  needsClass: boolean;
  /** Booked classes of the day, plus (for a variant, ADR-785) the other open ones. */
  hasBookedClasses: boolean;
  slotId: string;
  source: ProgrammingSource;
  workoutId: string;
  classHasWorkout: boolean;
}): string | null {
  if (input.needsClass && !input.hasBookedClasses) return "programmingDialogNoClass";
  if (input.needsClass && !input.slotId) return "programmingMissingClass";
  if (sourceUsesClassWorkout(input.source) && !input.classHasWorkout) return "memberProgrammingClassHasNoWorkout";
  if (input.source === "library" && !input.workoutId) return "programmingMissingWod";
  return null;
}

/**
 * A calendar day ("2026-10-29") as the locale writes it. The day is a plain
 * date, not an instant: it is read and formatted in UTC so no device or gym
 * time zone can move it to the day before or after.
 */
export function dayFormatter(locale: string, options: Intl.DateTimeFormatOptions) {
  const format = new Intl.DateTimeFormat(locale, { ...options, timeZone: "UTC" });
  const instant = (day: string) => {
    const [year, month, date] = day.split("-").map(Number);
    return new Date(Date.UTC(year, month - 1, date, 12));
  };
  return {
    format: (day: string) => format.format(instant(day)),
    formatRange: (from: string, to: string) => format.formatRange(instant(from), instant(to)),
  };
}
