import { describe, expect, it } from "vitest";

import {
  MEMBER_PROGRAMMING_MODES,
  canProgramMorePeople,
  classTakesVariant,
  offerableClasses,
  dayFormatter,
  modeRequiresBookedClass,
  modeRequiresProgrammingEntitlement,
  programmingBlocker,
  programmingSources,
  programmingSuccessKey,
  sourceOpensEditor,
  sourceUsesClassWorkout,
} from "@/lib/member-programming";

describe("member programming rules (ADR-125)", () => {
  it("offers the member's own class version first and the class-wide swap last", () => {
    expect(MEMBER_PROGRAMMING_MODES).toEqual(["class_variant", "personal", "class_workout"]);
  });

  it("requires a booked class only for class-bound modes", () => {
    expect(modeRequiresBookedClass("class_variant")).toBe(true);
    expect(modeRequiresBookedClass("class_workout")).toBe(true);
    expect(modeRequiresBookedClass("personal")).toBe(false);
  });

  it("requires the personal-programming package grant only for a separate workout (ADR-785: a variation needs none)", () => {
    expect(modeRequiresProgrammingEntitlement("class_variant")).toBe(false);
    expect(modeRequiresProgrammingEntitlement("personal")).toBe(true);
    expect(modeRequiresProgrammingEntitlement("class_workout")).toBe(false);
  });

  it("chooses role- and mode-aware success copy", () => {
    expect(programmingSuccessKey("athlete", "class_workout")).toBe("featurePersonalWodAssigned");
    expect(programmingSuccessKey("member", "class_variant")).toBe("memberProgrammingVariantCreated");
    expect(programmingSuccessKey("member", "personal")).toBe("memberProgrammingPersonalAssigned");
    expect(programmingSuccessKey("member", "class_workout")).toBe("featureClassWodAttached");
  });
});

describe("programming dialog steps", () => {
  const ready = {
    needsClass: true,
    hasBookedClasses: true,
    slotId: "slot-1",
    source: "library" as const,
    workoutId: "w-1",
    classHasWorkout: true,
  };

  it("offers class-based sources only for a member's own class version, adapting first", () => {
    expect(programmingSources("member", "class_variant")).toEqual(["adapt_class", "class_as_is", "library", "new"]);
    expect(programmingSources("member", "personal")).toEqual(["library", "new"]);
    expect(programmingSources("member", "class_workout")).toEqual(["library", "new"]);
    expect(programmingSources("athlete", "class_variant")).toEqual(["library", "new"]);
  });

  it("opens the editor only for sources that make a new workout", () => {
    expect(sourceOpensEditor("adapt_class")).toBe(true);
    expect(sourceOpensEditor("new")).toBe(true);
    expect(sourceOpensEditor("class_as_is")).toBe(false);
    expect(sourceOpensEditor("library")).toBe(false);
    expect(sourceUsesClassWorkout("class_as_is")).toBe(true);
    expect(sourceUsesClassWorkout("new")).toBe(false);
  });

  it("adds more people except when the whole class already gets the change", () => {
    expect(canProgramMorePeople("member", "class_workout")).toBe(false);
    expect(canProgramMorePeople("member", "class_variant")).toBe(true);
    expect(canProgramMorePeople("athlete", "class_workout")).toBe(true);
  });

  it("names the first missing step, in the order the dialog asks for them", () => {
    expect(programmingBlocker(ready)).toBeNull();
    expect(programmingBlocker({ ...ready, hasBookedClasses: false, slotId: "" })).toBe("programmingDialogNoClass");
    expect(programmingBlocker({ ...ready, slotId: "", workoutId: "" })).toBe("programmingMissingClass");
    expect(programmingBlocker({ ...ready, source: "adapt_class", classHasWorkout: false })).toBe("memberProgrammingClassHasNoWorkout");
    expect(programmingBlocker({ ...ready, workoutId: "" })).toBe("programmingMissingWod");
    expect(programmingBlocker({ ...ready, needsClass: false, hasBookedClasses: false, slotId: "", source: "new" })).toBeNull();
  });
});

describe("dayFormatter", () => {
  it("writes the calendar day itself, never the day before or after", () => {
    const long = dayFormatter("el", { weekday: "long", day: "numeric", month: "long" });
    expect(long.format("2026-10-29")).toBe("Πέμπτη 29 Οκτωβρίου");
    expect(dayFormatter("en", { day: "numeric", month: "short" }).formatRange("2026-10-28", "2026-11-03")).toMatch(/Oct 28.*Nov 3/);
  });
});

describe("classes a variation can go to (ADR-785)", () => {
  const now = Date.parse("2026-11-28T10:00:00Z");
  const slot = (id: string, at: string, extra: { duration_minutes?: number; cancelled_at?: string | null } = {}) => ({
    id,
    scheduled_at: at,
    duration_minutes: 60,
    cancelled_at: null,
    ...extra,
  });

  it("takes a variation until the class ends, also while it runs, never when cancelled", () => {
    expect(classTakesVariant(slot("a", "2026-11-28T11:00:00Z"), now)).toBe(true);
    expect(classTakesVariant(slot("b", "2026-11-28T09:30:00Z"), now)).toBe(true);
    expect(classTakesVariant(slot("c", "2026-11-28T08:00:00Z"), now)).toBe(false);
    expect(classTakesVariant(slot("d", "2026-11-28T11:00:00Z", { cancelled_at: "2026-11-27T10:00:00Z" }), now)).toBe(false);
  });

  it("offers the open classes the member has not booked, in time order", () => {
    const slots = [
      slot("late", "2026-11-28T18:00:00Z"),
      slot("booked", "2026-11-28T12:00:00Z"),
      slot("ended", "2026-11-28T07:00:00Z"),
      slot("early", "2026-11-28T11:00:00Z"),
    ];
    expect(offerableClasses(slots, new Set(["booked"]), now).map((entry) => entry.id)).toEqual(["early", "late"]);
  });
});
