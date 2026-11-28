import { describe, expect, it } from "vitest";

import { activityLogQuery } from "@/api/activity-log";

import {
  actorsOf,
  canReadActivityLog,
  changesOf,
  dayKey,
  groupByDay,
  mainRole,
  periodOf,
  personName,
  readableAreas,
  relativeDay,
  sharedField,
  shownReason,
} from "./activity-log-model";
import { entry } from "./activity-log-test-utils";

describe("activity log model (ADR-760)", () => {
  it("opens the log for anyone with a view_activity_* capability", () => {
    expect(canReadActivityLog({ role: "coach", capabilities: { view_activity_classes: "all" } })).toBe(true);
    expect(canReadActivityLog({ role: "coach", capabilities: { view_activity_staff_pay: "own" } })).toBe(true);
    expect(canReadActivityLog({ role: "member", capabilities: { book_classes: "all" } })).toBe(false);
    expect(canReadActivityLog(null)).toBe(false);
  });

  it("offers only the reader's areas, in the canonical order", () => {
    expect(readableAreas(["staff_pay", "money", "nonsense"])).toEqual(["money", "staff_pay"]);
    expect(readableAreas(undefined)).toEqual([]);
  });

  it("groups by the box's day, not the device's", () => {
    // 23:30 UTC on the 22nd is already the 23rd in Athens.
    const late = entry({ id: "a", occurred_at: "2026-11-22T23:30:00Z" });
    const early = entry({ id: "b", occurred_at: "2026-11-22T21:00:00Z" });
    expect(dayKey(late.occurred_at, "Europe/Athens")).toBe("2026-11-23");
    expect(groupByDay([late, early], "Europe/Athens").map((group) => [group.day, group.entries.map((row) => row.id)])).toEqual([
      ["2026-11-23", ["a"]],
      ["2026-11-22", ["b"]],
    ]);
    expect(groupByDay([late, early], "UTC")).toHaveLength(1);
  });

  it("names today and yesterday on the box's clock", () => {
    const now = new Date("2026-11-23T10:00:00Z");
    expect(relativeDay("2026-11-23", now, "Europe/Athens")).toBe("today");
    expect(relativeDay("2026-11-22", now, "Europe/Athens")).toBe("yesterday");
    expect(relativeDay("2026-11-20", now, "Europe/Athens")).toBeNull();
  });

  it("shows a deleted account as «Διαγραμμένο μέλος» without its reason or changes (9A)", () => {
    const gone = entry({ redacted: true, person: { id: "p", name: null }, reason: "secret", details: { changes: [{ field: "status", before: "a", after: "b" }] } });
    expect(personName(gone, "Deleted member")).toBe("Deleted member");
    expect(shownReason(gone)).toBeNull();
    expect(changesOf(gone)).toEqual([]);
    expect(periodOf(gone)).toBeNull();
    expect(personName(entry({ person: { id: "p", name: "Maria" } }), "Deleted member")).toBe("Maria");
    expect(personName(entry({ person: null }), "Deleted member")).toBeNull();
  });

  it("reads before → after and the period from the details", () => {
    const row = entry({ details: { changes: [{ field: "ends_on", before: "2026-11-30", after: null }], starts_on: "2026-11-24", ends_on: "2026-12-07" } });
    expect(changesOf(row)).toEqual([{ field: "ends_on", before: "2026-11-30", after: null }]);
    expect(periodOf(row)).toEqual({ from: "2026-11-24", to: "2026-12-07" });
    expect(shownReason(entry({ reason: "   " }))).toBeNull();
  });

  it("names an actor by their most senior role and lists the staff seen", () => {
    expect(mainRole(["coach", "admin"])).toBe("admin");
    expect(mainRole([])).toBeNull();
    const rows = [
      entry({ id: "1", actor: { id: "s1", name: "Eleni", roles: ["front_desk"] } }),
      entry({ id: "2", actor: { id: "s1", name: "Eleni", roles: ["front_desk"] } }),
      entry({ id: "3", actor: null }),
    ];
    expect(actorsOf(rows)).toEqual([{ id: "s1", name: "Eleni" }]);
  });

  it("always sends the share choice", () => {
    expect(sharedField(false)).toEqual({ reason_shared: false });
    expect(sharedField(true)).toEqual({ reason_shared: true });
  });

  it("builds the list's query from the filters", () => {
    expect(activityLogQuery({})).toBe("");
    expect(activityLogQuery({ areas: ["money", "packages"], person_id: "p1", actor_id: "s1", from: "2026-11-01", to: "2026-11-23", q: "  ankle " }, "c1")).toBe(
      "?areas=money%2Cpackages&person_id=p1&actor_id=s1&from=2026-11-01&to=2026-11-23&q=ankle&cursor=c1",
    );
  });
});
