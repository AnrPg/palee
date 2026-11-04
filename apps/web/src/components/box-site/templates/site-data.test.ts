import { describe, expect, it } from "vitest";

import { balanceTiles, countdown, heroSpansAll, nextClass, normalizeSite, scheduleDays, storyKinds, visibleSections } from "./site-data";
import { ALL_SECTIONS, BASIC, boxPage, boxSite, NOW } from "./site.test-fixtures";

describe("nextClass (in the box's time zone)", () => {
  const site = boxSite();

  it("finds the first class that has not started, with a countdown", () => {
    const next = nextClass(site.timetable, "Europe/Athens", NOW);
    expect(next).toMatchObject({ id: "t1", time: "17:00", dayOffset: 0, weekday: 3, inSeconds: 7 * 3600 });
  });

  it("counts days in the box's zone, not the visitor's", () => {
    // 22:30 in Athens is still Wednesday: 07:00 on Thursday is tomorrow there.
    expect(nextClass(site.timetable, "Europe/Athens", Date.parse("2026-11-04T20:30:00Z"))).toMatchObject({ id: "t2", time: "07:00", dayOffset: 1, weekday: 4 });
    // 01:30 on Thursday in Athens is 18:30 on Wednesday in New York.
    const night = Date.parse("2026-11-04T23:30:00Z");
    expect(nextClass(site.timetable, "Europe/Athens", night)).toMatchObject({ id: "t2", dayOffset: 0 });
    expect(nextClass(site.timetable, "America/New_York", night)).toMatchObject({ id: "t2", time: "00:00", dayOffset: 1 });
  });

  it("stands in the first class without a countdown on the server", () => {
    expect(nextClass(site.timetable, "Europe/Athens", null)).toMatchObject({ id: "t1", inSeconds: 0, dayOffset: 0 });
  });

  it("has nothing once every class has started", () => {
    expect(nextClass(site.timetable, "Europe/Athens", Date.parse("2026-11-06T00:00:00Z"))).toBeNull();
  });
});

describe("countdown", () => {
  it("shows hours, minutes and seconds under a day", () => {
    expect(countdown(2 * 3600 + 43 * 60 + 39)).toEqual({ kind: "clock", text: "02:43:39" });
    expect(countdown(-5)).toEqual({ kind: "clock", text: "00:00:00" });
  });
  it("shows whole days above", () => {
    expect(countdown(86_400 * 2 + 50)).toEqual({ kind: "days", days: 2 });
  });
});

describe("balanceTiles (no holes on the phone's two columns)", () => {
  const tile = (key: string, wide = false) => ({ key, wide });

  it("makes the last single tile wide when the singles are odd", () => {
    const out = balanceTiles([tile("a"), tile("b", true), tile("c"), tile("d")]);
    expect(out.map((entry) => entry.wide)).toEqual([false, true, false, true]);
  });
  it("leaves an even number of singles alone and never mutates its input", () => {
    const input = [tile("a"), tile("b")];
    expect(balanceTiles(input).map((entry) => entry.wide)).toEqual([false, false]);
    balanceTiles([tile("x")]);
    expect(input[0]!.wide).toBe(false);
  });
  it("lets the hero span the row with fewer than three tiles", () => {
    expect(heroSpansAll(2)).toBe(true);
    expect(heroSpansAll(3)).toBe(false);
  });
});

describe("storyKinds", () => {
  it("builds the rings from the visible sections in a fixed order", () => {
    expect(storyKinds(["reviews", "coaches", "photos", "wod"])).toEqual(["wod", "space", "coaches", "reviews"]);
    expect(storyKinds(["about", "packages"])).toEqual([]);
  });
});

describe("visibleSections", () => {
  const page = boxPage();

  it("keeps every section that is on and has data", () => {
    expect(visibleSections({ site: boxSite(), page, packages: 3, gallery: 1 })).toEqual(ALL_SECTIONS);
  });

  it("hides a section that is on but empty", () => {
    const site = boxSite({ timetable: [], wod: [], faq: [] });
    const shown = visibleSections({ site, page, packages: 0, gallery: 1 });
    expect(shown).not.toContain("schedule");
    expect(shown).not.toContain("wod");
    expect(shown).not.toContain("faq");
    expect(shown).not.toContain("packages");
  });

  it("shows only what the owner switched on", () => {
    expect(visibleSections({ site: boxSite({ sections: BASIC }), page, packages: 3, gallery: 1 })).toEqual(BASIC);
  });
});

describe("normalizeSite", () => {
  it("tolerates an API without the ADR-530 fields", () => {
    const site = normalizeSite({ slug: "old", sections: ["hero"] } as never);
    expect(site).toMatchObject({ template: "arena", palette: "palee", appearance: "auto", calm_motion: false, programmes: [], stats: null, phone: null });
    expect(site.photos).toEqual({ items: [], video: null });
  });
  it("falls back to «Αρένα» for an unknown template", () => {
    expect(normalizeSite({ template: "neon" } as never).template).toBe("arena");
  });
});

describe("scheduleDays", () => {
  it("groups the week's classes by the box's day", () => {
    const days = scheduleDays(boxSite().timetable, "Europe/Athens", "el", {}, NOW);
    expect(days.filter((day) => day.entries.length).map((day) => day.entries.map((entry) => entry.id))).toEqual([["t1"], ["t2"]]);
    expect(days.length).toBe(7);
    expect(days[0]!.entries[0]).toMatchObject({ time: "17:00", minutes: 60 });
  });
});
