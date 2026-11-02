import { afterEach, describe, expect, it } from "vitest";

import type { ClassVisitPerson, FitnessDomain } from "@/api/training-floor";

import {
  DEFAULT_LEADERBOARD_FILTERS,
  advancedActive,
  ageGroupFor,
  ageGroupLabel,
  birthYearOptions,
  calendarOfferPending,
  dayTagView,
  defaultNoteAudience,
  googleCalendarUrl,
  leaderboardChips,
  leaderboardQuery,
  newcomers,
  orderedDomains,
  reasonValue,
  rememberCalendarOffer,
  rowBadges,
  snapshotLines,
  toggleChip,
} from "./training-floor";

describe("leaderboard filters (ADR-356, mockup d2 A)", () => {
  it("groups ages like the API: by the age reached during the year", () => {
    expect(ageGroupFor(null, 2026)).toBeNull();
    expect(ageGroupFor(2010, 2026)).toBe("under_18");
    expect(ageGroupFor(2008, 2026)).toBe("18_34");
    expect(ageGroupFor(1992, 2026)).toBe("18_34");
    expect(ageGroupFor(1991, 2026)).toBe("35_39");
    expect(ageGroupFor(1987, 2026)).toBe("35_39");
    expect(ageGroupFor(1986, 2026)).toBe("40_44");
    expect(ageGroupFor(1961, 2026)).toBe("65_plus");
    expect(ageGroupLabel("35_39")).toBe("35–39");
    expect(ageGroupLabel("under_18")).toBe("<18");
    expect(ageGroupLabel("65_plus")).toBe("65+");
  });

  it("offers only the viewer's own slices, with «Όλοι» on by default", () => {
    const chips = leaderboardChips(DEFAULT_LEADERBOARD_FILTERS, {
      division: "women",
      birthYear: 1989,
      year: 2026,
      scale: { slug: "rx", label: "RX" },
    });
    expect(chips.map((chip) => chip.kind)).toEqual(["all", "division", "age", "scale"]);
    expect(chips[0]).toEqual({ kind: "all", on: true });
    expect(chips[2]).toMatchObject({ kind: "age", value: "35_39", on: false });

    const bare = leaderboardChips(DEFAULT_LEADERBOARD_FILTERS, { division: null, birthYear: null, year: 2026, scale: null });
    expect(bare).toEqual([{ kind: "all", on: true }]);
  });

  it("toggles slices together and «Όλοι» clears them", () => {
    let filters = toggleChip(DEFAULT_LEADERBOARD_FILTERS, { kind: "division", value: "women", on: false });
    filters = toggleChip(filters, { kind: "age", value: "35_39", on: false });
    expect(filters).toMatchObject({ division: "women", ageGroup: "35_39" });
    expect(toggleChip(filters, { kind: "division", value: "women", on: true }).division).toBeNull();
    expect(toggleChip(filters, { kind: "all", on: false })).toMatchObject({ division: null, ageGroup: null, scale: null });
  });

  it("builds the API query; the branch is the home branch, or the whole box without one", () => {
    expect(leaderboardQuery(DEFAULT_LEADERBOARD_FILTERS, { date: "2026-11-03", homeLocationId: "loc-1" })).toEqual({
      date: "2026-11-03",
      window: "day",
      scope: "box",
    });
    const branch = { ...DEFAULT_LEADERBOARD_FILTERS, scope: "branch" as const, buddies: true, scale: "rx", window: "month" as const };
    expect(leaderboardQuery(branch, { date: "2026-11-03", homeLocationId: "loc-1" })).toEqual({
      date: "2026-11-03",
      window: "month",
      scale: "rx",
      scope: "branch",
      location_id: "loc-1",
      buddies: true,
    });
    expect(leaderboardQuery(branch, { date: "2026-11-03", homeLocationId: null }).scope).toBe("box");
    expect(advancedActive(DEFAULT_LEADERBOARD_FILTERS)).toBe(false);
    expect(advancedActive(branch)).toBe(true);
  });

  it("offers birth years from 14 to 90 years old, newest first", () => {
    const years = birthYearOptions(2026);
    expect(years[0]).toBe(2012);
    expect(years.at(-1)).toBe(1936);
  });
});

describe("day tags (ADR-357, mockup d3 A)", () => {
  it("says it in words, with a tone that is never the only signal", () => {
    expect(dayTagView("mixed")).toEqual({ key: "dayTagMixed", tone: "warning" });
    expect(dayTagView("all_assigned").tone).toBe("success");
    expect(dayTagView("not_assigned").tone).toBe("danger");
    expect(dayTagView("none").key).toBe("dayTagNone");
  });

  it("reads a snapshot's text and sections as lines", () => {
    expect(
      snapshotLines({
        title: "Fran",
        content: "21-15-9\nThrusters 43 kg",
        sections: [{ name: "For time", exercises: [{ name: "Thrusters" }, { name: "Pull-ups" }] }],
      }),
    ).toEqual(["21-15-9", "Thrusters 43 kg", "For time: Thrusters · Pull-ups"]);
    expect(snapshotLines({})).toEqual([]);
  });
});

describe("fitness profile (ADR-358, mockup d6 A)", () => {
  it("keeps five domains in a fixed order, untested ones included", () => {
    const metcon: FitnessDomain = { domain: "metcon", score: 50, confidence: "low", reasons: [], stale: false };
    const ordered = orderedDomains([metcon]);
    expect(ordered.map((domain) => domain.domain)).toEqual(["strength", "power", "gymnastics", "monostructural", "metcon"]);
    expect(ordered[0].score).toBeNull();
    expect(ordered[4]).toBe(metcon);
  });

  it("writes PR values as kg, reps or m:ss", () => {
    expect(reasonValue(360, "mins_secs", "en")).toBe("6:00");
    expect(reasonValue(185.5, "mins_secs", "en")).toBe("3:06");
    expect(reasonValue(116.5, "kg", "el")).toBe("116,5 kg");
    expect(reasonValue(20, "reps", "en")).toBe("20");
  });
});

describe("visit badges (ADR-359, mockup e1 B)", () => {
  const person = (badges: ClassVisitPerson["badges"], booking_id = "b1"): ClassVisitPerson => ({
    badges,
    booking_id,
    user_id: "u1",
    brought_by: null,
    guest_name: null,
    via: null,
  });

  it("«Νέοι σήμερα» are first visits and trial seats", () => {
    const people = [person(["first_visit", "came_via_event"], "b1"), person(["guest"], "b2"), person(["trial"], "b3"), person([], "b4")];
    expect(newcomers(people).map((entry) => entry.booking_id)).toEqual(["b1", "b3"]);
    expect(newcomers(null)).toEqual([]);
  });

  it("a row leaves out how they came (shown in words) and, on request, the trial it already tags", () => {
    expect(rowBadges(["trial", "first_visit", "came_via_referral"], { skipTrial: true })).toEqual(["first_visit"]);
    expect(rowBadges(["trial", "guest"])).toEqual(["trial", "guest"]);
    expect(rowBadges(null)).toEqual([]);
  });
});

describe("calendar offer (ADR-359, mockup e4 A)", () => {
  afterEach(() => window.localStorage.clear());

  it("asks once per person on this device, whatever the answer", () => {
    expect(calendarOfferPending(null)).toBe(false);
    expect(calendarOfferPending("u1")).toBe(true);
    rememberCalendarOffer("u1", "no");
    expect(calendarOfferPending("u1")).toBe(false);
    expect(calendarOfferPending("u2")).toBe(true);
  });

  it("opens Google Calendar's add-by-URL with the private feed", () => {
    expect(googleCalendarUrl("webcal://palee.app/api/calendar/feed.ics?token=a&b=1")).toBe(
      "https://calendar.google.com/calendar/render?cid=webcal%3A%2F%2Fpalee.app%2Fapi%2Fcalendar%2Ffeed.ics%3Ftoken%3Da%26b%3D1",
    );
  });
});

describe("note audience (ADR-359, mockup e5 A)", () => {
  it("a coach starts from «Μόνο εγώ», others from the staff, the desk only for the staff", () => {
    expect(defaultNoteAudience(["coach"], true)).toBe("private");
    expect(defaultNoteAudience(["owner"], true)).toBe("staff");
    expect(defaultNoteAudience(["front_desk"], false)).toBe("staff");
    expect(defaultNoteAudience(["coach"], false)).toBe("staff");
  });
});
