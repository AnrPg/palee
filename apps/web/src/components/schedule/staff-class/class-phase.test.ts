import { describe, expect, it } from "vitest";

import { classPhase, minutesUntilStart, nextPhaseChange, staffCheckInOpen } from "./class-phase";

const slot = { scheduled_at: "2026-11-23T10:00:00Z", duration_minutes: 60 };
const at = (iso: string) => Date.parse(iso);

describe("classPhase", () => {
  it("is upcoming more than 30 minutes before the start", () => {
    expect(classPhase(slot, at("2026-11-23T09:29:00Z"))).toBe("upcoming");
  });
  it("is soon in the last 30 minutes", () => {
    expect(classPhase(slot, at("2026-11-23T09:30:00Z"))).toBe("soon");
    expect(classPhase(slot, at("2026-11-23T09:59:59Z"))).toBe("soon");
  });
  it("is live from the start until the end", () => {
    expect(classPhase(slot, at("2026-11-23T10:00:00Z"))).toBe("live");
    expect(classPhase(slot, at("2026-11-23T10:59:00Z"))).toBe("live");
  });
  it("is ended after the class's length", () => {
    expect(classPhase(slot, at("2026-11-23T11:00:00Z"))).toBe("ended");
  });
});

describe("minutesUntilStart", () => {
  it("rounds up and stops at zero", () => {
    expect(minutesUntilStart(slot, at("2026-11-23T09:40:30Z"))).toBe(20);
    expect(minutesUntilStart(slot, at("2026-11-23T10:05:00Z"))).toBe(0);
  });
});

describe("staffCheckInOpen", () => {
  it("follows the box's window before the start", () => {
    expect(staffCheckInOpen(slot, at("2026-11-23T09:44:00Z"), 15)).toBe(false);
    expect(staffCheckInOpen(slot, at("2026-11-23T09:45:00Z"), 15)).toBe(true);
  });
  it("uses the default window when the rules are unknown", () => {
    expect(staffCheckInOpen(slot, at("2026-11-23T09:29:00Z"), null)).toBe(false);
    expect(staffCheckInOpen(slot, at("2026-11-23T09:30:00Z"), undefined)).toBe(true);
  });
  it("stays open after the class, for a forgotten check-in", () => {
    expect(staffCheckInOpen(slot, at("2026-11-24T10:00:00Z"), 30)).toBe(true);
  });
});

describe("nextPhaseChange", () => {
  it("is the nearest later boundary", () => {
    expect(nextPhaseChange(slot, at("2026-11-23T09:00:00Z"), 15)).toBe(at("2026-11-23T09:30:00Z"));
    expect(nextPhaseChange(slot, at("2026-11-23T09:35:00Z"), 15)).toBe(at("2026-11-23T09:45:00Z"));
    expect(nextPhaseChange(slot, at("2026-11-23T10:30:00Z"), 15)).toBe(at("2026-11-23T11:00:00Z"));
  });
  it("is null once the class has ended", () => {
    expect(nextPhaseChange(slot, at("2026-11-23T12:00:00Z"), 15)).toBeNull();
  });
});
