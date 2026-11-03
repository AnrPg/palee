import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";

import { DEFAULT_RULES, doorAnswer, hoursToSpans, logTone, matchesLogFilter, rangeError, rulesOf, spansToHours } from "./doors-model";

describe("doors model (W10 screens 4–6)", () => {
  it("fills a door's rules over the defaults", () => {
    expect(rulesOf(null)).toEqual(DEFAULT_RULES);
    expect(rulesOf({ who: "members", unlock_seconds: 8 })).toEqual({ ...DEFAULT_RULES, who: "members", unlock_seconds: 8 });
    expect(rulesOf({ who: "anyone" }).who).toBe("booked_or_covered");
  });

  it("keeps the API's ranges for the advanced numbers", () => {
    expect(rangeError("unlock_seconds", 5)).toBeNull();
    expect(rangeError("unlock_seconds", 0)).toEqual({ min: 1, max: 30 });
    expect(rangeError("window_before_minutes", 181)).toEqual({ min: 0, max: 180 });
  });

  it("turns door hours into the branch hours editor and back, grouping equal times", () => {
    const hours = [{ days: [1, 2, 3, 4, 5], from: "06:00", to: "22:00" }, { days: [6], from: "08:00", to: "14:00" }];
    const spans = hoursToSpans(hours);
    expect(spans).toHaveLength(6);
    expect(spans[0]).toEqual({ weekday: 1, opens: "06:00", closes: "22:00" });
    expect(spansToHours(spans)).toEqual(hours);
  });

  it("filters the access log and gives each line its tone", () => {
    expect(matchesLogFilter({ kind: "denied", method: "qr" }, "problems")).toBe(true);
    expect(matchesLogFilter({ kind: "door_event", method: "provider" }, "problems")).toBe(true);
    expect(matchesLogFilter({ kind: "granted", method: "qr" }, "problems")).toBe(false);
    expect(matchesLogFilter({ kind: "staff_unlock", method: "staff" }, "staff")).toBe(true);
    expect(logTone("granted")).toBe("ok");
    expect(logTone("unlock_failed")).toBe("bad");
    expect(logTone("staff_unlock")).toBe("manual");
  });

  it("reads the door's answer after a scan", () => {
    expect(doorAnswer({ opened: true, reason: "booked_class", seconds: 5, door: { id: "d", name: "Main" } }, null)).toEqual({ kind: "opened", door: "Main", seconds: 5 });
    expect(doorAnswer(null, new ApiError(404, "x", { code: "no_door_here" }))).toEqual({ kind: "none" });
    expect(doorAnswer(null, new ApiError(403, "x", { code: "entry_denied", params: { reason: "no_booking_in_window", door: { name: "Main" } } }))).toEqual({
      kind: "denied",
      reason: "no_booking_in_window",
      door: "Main",
    });
    expect(doorAnswer(null, new ApiError(503, "x", { code: "door_offline" }))).toEqual({ kind: "offline" });
    expect(doorAnswer(null, new ApiError(409, "x", { code: "choose_door", params: { doors: [{ id: "a", name: "A" }] } }))).toEqual({ kind: "choose", doors: [{ id: "a", name: "A" }] });
    expect(doorAnswer(null, null)).toEqual({ kind: "none" });
    expect(doorAnswer(null, new Error("network"))).toEqual({ kind: "error" });
  });
});
