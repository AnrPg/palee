import { describe, expect, it } from "vitest";

import {
  activeCleanupFilterCount,
  cleanupQuery,
  EMPTY_CLEANUP_FILTERS,
  matchingQuickRange,
  quickRange,
} from "./finance-cleanup";

describe("finance cleanup filters", () => {
  it("sends only the filters in force, with the page", () => {
    expect(cleanupQuery(EMPTY_CLEANUP_FILTERS)).toEqual({});
    expect(
      cleanupQuery(
        { q: "  maria ", userId: "u1", packageId: "p1", from: "2026-11-01", to: "", kind: "receipt" },
        { cursor: "c1", limit: 30 },
      ),
    ).toEqual({ q: "maria", user_id: "u1", package_id: "p1", from: "2026-11-01", kind: "receipt", cursor: "c1", limit: "30" });
  });

  it("counts a date range once and never the search text", () => {
    expect(activeCleanupFilterCount({ ...EMPTY_CLEANUP_FILTERS, q: "x" })).toBe(0);
    expect(activeCleanupFilterCount({ ...EMPTY_CLEANUP_FILTERS, from: "2026-11-01", to: "2026-11-30", kind: "payment" })).toBe(2);
  });

  it("builds quick ranges on the gym's day, across month and year ends", () => {
    expect(quickRange("today", "2026-11-28")).toEqual({ from: "2026-11-28", to: "2026-11-28" });
    expect(quickRange("thisMonth", "2026-02-10")).toEqual({ from: "2026-02-01", to: "2026-02-28" });
    expect(quickRange("thisMonth", "2028-02-10")).toEqual({ from: "2028-02-01", to: "2028-02-29" });
    expect(quickRange("thisMonth", "2026-12-31")).toEqual({ from: "2026-12-01", to: "2026-12-31" });
    expect(quickRange("lastMonth", "2026-01-15")).toEqual({ from: "2025-12-01", to: "2025-12-31" });
    expect(quickRange("thisYear", "2026-11-28")).toEqual({ from: "2026-01-01", to: "2026-12-31" });
  });

  it("knows which quick range the dates are", () => {
    expect(matchingQuickRange({ from: "2026-11-01", to: "2026-11-30" }, "2026-11-28")).toBe("thisMonth");
    expect(matchingQuickRange({ from: "2026-11-02", to: "2026-11-30" }, "2026-11-28")).toBeNull();
    expect(matchingQuickRange({ from: "", to: "" }, "2026-11-28")).toBeNull();
  });
});
