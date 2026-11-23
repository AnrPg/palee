import { describe, expect, it } from "vitest";

import type { BoxScreenClass, BoxScreenToday } from "@/api/box-screens";

import {
  classesOnScreen,
  formatPairingCode,
  minutesUntil,
  newEntryKeys,
  nextChangeAt,
  normalizePairingCode,
  pairingCodeComplete,
  scaleLabel,
  scoreText,
  screenScene,
  tokenNeedsRenewal,
  untilFromTime,
} from "./box-screen";

const T = (time: string) => `2026-10-29T${time}:00Z`;
const ms = (time: string) => Date.parse(T(time));

function slot(id: string, start: string, end: string, extra: Partial<BoxScreenClass> = {}): BoxScreenClass {
  return {
    id,
    name: "CrossFit",
    class_type: "CrossFit",
    coach_name: "Νίκος",
    scheduled_at: T(start),
    ends_at: T(end),
    duration_minutes: 60,
    cancelled: false,
    location_id: null,
    workout_id: `w-${id}`,
    bookings: { names: ["Μαρία"], count: 1, capacity: 14, unnamed: 0, waitlist: 0 },
    ...extra,
  };
}

function today(focus: Partial<BoxScreenToday["focus"]> = {}): BoxScreenToday {
  return {
    box: { id: "org-1", name: "Box Κυψέλη" },
    screen: { id: "s1", name: "Αίθουσα 1", branch: null },
    date: "2026-10-29",
    time_zone: "UTC",
    server_now: T("17:52"),
    classes: [slot("a", "17:00", "18:00"), slot("b", "18:00", "19:00"), slot("x", "19:00", "20:00", { cancelled: true })],
    workouts: [
      { id: "w-a", title: "Cindy", type: "amrap", body: { kind: "free_text", text: "AMRAP 20", document: null, timer: null, structured: false } },
      { id: "w-b", title: "Fran", type: "for_time", body: { kind: "free_text", text: "21-15-9", document: null, timer: null, structured: false } },
    ],
    leaderboards: [{ workout_id: "w-b", score: null, entries: [{ name: "Ελένη", rank: 1, value: "3:42", unit: null, scale_level_slug: "rx" }] }],
    focus: { view: "preview", source: "auto", slot_id: "b", until: null, ...focus },
  };
}

describe("screenScene", () => {
  it("follows the class automatically: preview, timer, results, idle", () => {
    expect(screenScene(today({ view: "preview", slot_id: "b" }), ms("17:52"))).toMatchObject({ kind: "preview", slot: { id: "b" }, workout: { title: "Fran" } });
    expect(screenScene(today({ view: "timer", slot_id: "b" }), ms("18:10"))).toMatchObject({ kind: "timer", slot: { id: "b" }, leaderboard: { workout_id: "w-b" } });
    expect(screenScene(today({ view: "results", slot_id: "b" }), ms("19:10"))).toMatchObject({ kind: "results", slot: { id: "b" } });
    expect(screenScene(today({ view: "idle", slot_id: null }), ms("21:00"))).toEqual({ kind: "idle" });
  });

  it("shows what staff pinned", () => {
    expect(screenScene(today({ view: "wod", source: "staff", slot_id: null }), ms("17:30"))).toMatchObject({ kind: "wod", workout: { title: "Cindy" } });
    expect(screenScene(today({ view: "leaderboard", source: "staff", slot_id: "b" }), ms("17:30"))).toMatchObject({
      kind: "leaderboard",
      workout: { title: "Fran" },
      leaderboard: { workout_id: "w-b" },
    });
    expect(screenScene(today({ view: "bookings", source: "staff", slot_id: null }), ms("17:55"))).toMatchObject({ kind: "bookings", slot: { id: "a" } });
    expect(screenScene(today({ view: "timer", source: "staff", slot_id: null }), ms("17:30"))).toMatchObject({ kind: "timer", slot: { id: "a" } });
  });

  it("plays one pinned class through its own phases", () => {
    const pinned = today({ view: "class", source: "staff", slot_id: "b" });
    expect(screenScene(pinned, ms("17:00")).kind).toBe("preview");
    expect(screenScene(pinned, ms("18:30")).kind).toBe("timer");
    expect(screenScene(pinned, ms("20:30")).kind).toBe("results");
    expect(screenScene(today({ view: "class", source: "staff", slot_id: "gone" }), ms("18:30")).kind).toBe("idle");
  });

  it("is idle when there is nothing to show", () => {
    const empty = { ...today({ view: "wod", source: "staff", slot_id: null }), classes: [], workouts: [] };
    expect(screenScene(empty, ms("12:00"))).toEqual({ kind: "idle" });
    expect(screenScene({ ...empty, focus: { ...empty.focus, view: "bookings" } }, ms("12:00"))).toEqual({ kind: "idle" });
  });
});

describe("nextChangeAt", () => {
  it("is the next start, end, end of results or end of a pin, skipping cancelled classes", () => {
    expect(nextChangeAt(today(), ms("17:52"))).toBe(ms("18:00"));
    expect(nextChangeAt(today(), ms("19:00"))).toBe(ms("19:30"));
    expect(nextChangeAt(today({ until: T("18:45") }), ms("18:31"))).toBe(ms("18:45"));
    expect(nextChangeAt(today(), ms("19:31"))).toBeNull();
  });
});

describe("pairing code", () => {
  it("ignores case, spaces and dashes and shows ABCD-EFGH", () => {
    expect(normalizePairingCode(" acef-3467 ")).toBe("ACEF3467");
    expect(formatPairingCode("acef3")).toBe("ACEF-3");
    expect(formatPairingCode("acef34679xyz")).toBe("ACEF-3467");
    expect(pairingCodeComplete("acef 3467")).toBe(true);
    expect(pairingCodeComplete("acef-346")).toBe(false);
  });

  it("renews the display token once less than 60 days are left", () => {
    const now = ms("12:00");
    expect(tokenNeedsRenewal(new Date(now + 89 * 86_400_000).toISOString(), now)).toBe(false);
    expect(tokenNeedsRenewal(new Date(now + 59 * 86_400_000).toISOString(), now)).toBe(true);
    expect(tokenNeedsRenewal("nonsense", now)).toBe(true);
  });
});

describe("staff pin", () => {
  it("«Έως» is the next time the box's clock shows it, within 24 hours", () => {
    expect(untilFromTime("19:30", "Europe/Athens", ms("12:00"))).toBe("2026-10-29T17:30:00.000Z");
    expect(untilFromTime("09:00", "Europe/Athens", ms("12:00"))).toBe("2026-10-30T07:00:00.000Z");
  });

  it("lists the classes of the screen's branch and of the whole box", () => {
    const slots = [
      { id: "1", location_id: "k" },
      { id: "2", location_id: "p" },
      { id: "3", location_id: null },
      { id: "4", location_id: "k", cancelled_at: T("08:00") },
    ];
    expect(classesOnScreen(slots, "k").map((s) => s.id)).toEqual(["1", "3"]);
    expect(classesOnScreen(slots, null).map((s) => s.id)).toEqual(["1", "2", "3"]);
  });
});

describe("leaderboard text", () => {
  it("names scales and scores the way people read them", () => {
    expect(scaleLabel("rx")).toBe("Rx");
    expect(scaleLabel("scaled")).toBe("Scaled");
    expect(scaleLabel("foundations-plus")).toBe("Foundations plus");
    expect(scaleLabel(null)).toBeNull();
    expect(scoreText({ value: "120", unit: "kg" })).toBe("120 kg");
    expect(scoreText({ value: "3:42", unit: null })).toBe("3:42");
    expect(minutesUntil(T("18:00"), ms("17:52"))).toBe(8);
  });

  it("marks the scores that just came in", () => {
    const before = [{ name: "Ελένη", rank: 1, value: "3:42", unit: null, scale_level_slug: "rx" }];
    const after = [...before, { name: "Μαρία", rank: 2, value: "3:58", unit: null, scale_level_slug: "rx" }];
    expect(newEntryKeys(null, after)).toEqual([]);
    expect(newEntryKeys(before, after)).toEqual(["Μαρία|3:58"]);
  });
});

describe("ADR-746: several WODs in a class", () => {
  function multi(focus: Partial<BoxScreenToday["focus"]> = {}): BoxScreenToday {
    const base = today(focus);
    return {
      ...base,
      classes: [
        slot("b", "18:00", "19:00", { workout_ids: ["w-b", "w-a"], live_workout_id: "w-a" }),
        slot("c", "18:00", "19:00", { workout_id: "w-c" }),
      ],
      workouts: [
        ...base.workouts,
        { id: "w-c", title: "Helen", type: "for_time", body: { kind: "free_text", text: "3 RFT", document: null, timer: null, structured: false } },
      ],
    };
  }

  it("follows the class's «Τώρα»", () => {
    expect(screenScene(multi({ view: "timer", slot_id: "b" }), ms("18:10"))).toMatchObject({ kind: "timer", workout: { id: "w-a" } });
  });

  it("shows the WOD a pin chose, only when it is one of the class's", () => {
    expect(screenScene(multi({ view: "timer", source: "staff", slot_id: "b", workout_id: "w-b" }), ms("18:10"))).toMatchObject({
      kind: "timer",
      workout: { id: "w-b" },
      workoutId: "w-b",
    });
    expect(screenScene(multi({ view: "timer", source: "staff", slot_id: "b", workout_id: "w-c" }), ms("18:10"))).toMatchObject({
      workout: { id: "w-a" },
    });
  });

  it("shares the screen with the class that runs at the same time", () => {
    expect(screenScene(multi({ view: "timer", slot_id: "b", split_slot_id: "c" }), ms("18:10"))).toMatchObject({
      kind: "timer",
      slot: { id: "b" },
      split: { id: "c" },
    });
    expect(screenScene(multi({ view: "timer", slot_id: "b", split_slot_id: "b" }), ms("18:10"))).toMatchObject({ split: null });
  });

  it("shows a leaderboard for each other WOD of the class after it", () => {
    const scene = screenScene(multi({ view: "results", slot_id: "b" }), ms("19:10"));
    expect(scene).toMatchObject({ kind: "results", workout: { id: "w-a" } });
    expect(scene.kind === "results" ? (scene.others ?? []).map((other) => other.workout.id) : []).toEqual(["w-b"]);
  });
});
