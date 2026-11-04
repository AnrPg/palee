import { describe, expect, it } from "vitest";

import { notReportedCount } from "./AdminDashboard";

describe("notReportedCount (ADR-530)", () => {
  it("counts refused and failed reports only", () => {
    expect(notReportedCount({ counts: { accepted: 9, pending: 2, rejected: 1, failed: 2 } })).toBe(3);
  });

  it("counts none for a missing or malformed answer", () => {
    expect(notReportedCount(undefined)).toBe(0);
    expect(notReportedCount({} as never)).toBe(0);
    expect(notReportedCount({ counts: { rejected: "x" as unknown as number } })).toBe(0);
  });
});
