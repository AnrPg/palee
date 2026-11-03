import { describe, expect, it } from "vitest";

import { coachQueueCounts, mergeAgenda, openAppointmentSlots, slotsOnDay } from "@/components/admin/staff-home-agenda";

describe("mergeAgenda", () => {
  it("puts classes and appointments in one list by start time", () => {
    const merged = mergeAgenda(
      [
        { startsAt: "2026-11-03T18:00:00Z", entry: "crossfit-18" },
        { startsAt: "2026-11-03T07:00:00Z", entry: "crossfit-07" },
      ],
      [{ startsAt: "2026-11-03T11:00:00Z", entry: "pt-11" }],
    );
    expect(merged.map((item) => [item.kind, item.entry])).toEqual([
      ["class", "crossfit-07"],
      ["appointment", "pt-11"],
      ["class", "crossfit-18"],
    ]);
  });

  it("lists a class before an appointment at the same time", () => {
    const merged = mergeAgenda([{ startsAt: "2026-11-03T09:00:00Z", entry: "c" }], [{ startsAt: "2026-11-03T09:00:00Z", entry: "a" }]);
    expect(merged.map((item) => item.kind)).toEqual(["class", "appointment"]);
  });
});

describe("appointment slots", () => {
  it("drops cancelled slots, sorts, and tolerates a malformed answer", () => {
    expect(openAppointmentSlots(undefined)).toEqual([]);
    expect(openAppointmentSlots({})).toEqual([]);
    const slots = openAppointmentSlots<{ id: string; starts_at: string; cancelled_at?: string | null }>([
      { id: "b", starts_at: "2026-11-03T16:30:00Z" },
      { id: "x", starts_at: "2026-11-03T10:00:00Z", cancelled_at: "2026-11-02T10:00:00Z" },
      { id: "a", starts_at: "2026-11-03T11:00:00Z" },
    ]);
    expect(slots.map((slot) => slot.id)).toEqual(["a", "b"]);
  });

  it("keeps the slots of the same local day", () => {
    const now = new Date(2026, 10, 3, 9, 0);
    const today = new Date(2026, 10, 3, 17, 0).toISOString();
    const tomorrow = new Date(2026, 10, 4, 9, 0).toISOString();
    expect(slotsOnDay([{ starts_at: today }, { starts_at: tomorrow }], now)).toEqual([{ starts_at: today }]);
  });
});

describe("coachQueueCounts", () => {
  it("counts each queue and the overdue replies", () => {
    expect(
      coachQueueCounts({ replies: [{ overdue: true }, { overdue: false }], formReviews: [{}], scaling: [{}, {}, {}] }),
    ).toEqual({ replies: 2, overdueReplies: 1, formReviews: 1, scaling: 3 });
  });

  it("treats anything that is not a list as empty", () => {
    expect(coachQueueCounts({ replies: {}, formReviews: null, scaling: undefined })).toEqual({
      replies: 0,
      overdueReplies: 0,
      formReviews: 0,
      scaling: 0,
    });
  });
});
