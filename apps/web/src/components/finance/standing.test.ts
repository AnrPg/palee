import { describe, expect, it } from "vitest";

import { daysBetween, standingParts, type Standing } from "./standing";

const base: Standing = { status: "active", grace_until: null, access_until: null, outstanding_cents: 0, unpaid_since: null };
const today = "2026-11-09";

describe("standingParts (ADR-595)", () => {
  it("says nothing for a member in good standing", () => {
    expect(standingParts(base, today)).toEqual([]);
    expect(standingParts(null, today)).toEqual([]);
  });

  it("tells what is owed, since when, and the grace with its days left", () => {
    expect(
      standingParts({ ...base, status: "unpaid", outstanding_cents: 5000, unpaid_since: "2026-10-29", grace_until: "2026-11-11" }, today),
    ).toEqual([
      { key: "lineOwedSince", cents: 5000, date: "2026-10-29" },
      { key: "lineGrace", date: "2026-11-11", days: 2 },
    ]);
  });

  it("shows a grace on its last day and drops one that has passed", () => {
    expect(standingParts({ ...base, grace_until: today }, today)).toEqual([{ key: "lineGrace", date: today, days: 0 }]);
    expect(standingParts({ ...base, grace_until: "2026-11-08" }, today)).toEqual([]);
  });

  it("tells a former member the package they kept and what they still owe", () => {
    expect(standingParts({ ...base, status: "leaving", access_until: "2026-11-28", outstanding_cents: 5000 }, today)).toEqual([
      { key: "linePackageUntil", date: "2026-11-28" },
      { key: "lineOwed", cents: 5000 },
    ]);
    expect(standingParts({ ...base, status: "former", access_until: "2026-11-01" }, today)).toEqual([]);
  });

  it("ADR-612: names a grace or free access the box gave", () => {
    expect(standingParts({ ...base, status: "overdue", grace_until: "2026-11-30", benefit: "grace" }, today)).toEqual([
      { key: "lineBoxGrace", date: "2026-11-30", days: 21 },
    ]);
    expect(standingParts({ ...base, status: "comped", grace_until: "2026-11-10", benefit: "free_access" }, today)).toEqual([
      { key: "lineBoxFree", date: "2026-11-10", days: 1 },
    ]);
  });

  it("counts days across a month end", () => {
    expect(daysBetween("2026-11-29", "2026-12-02")).toBe(3);
  });
});
