import { describe, expect, it } from "vitest";

import { leaveRequest, renewableSubscriptions } from "./membership-leaving";

describe("leaveRequest (ADR-595)", () => {
  it("sends only the reason: the day follows the member's own rules", () => {
    expect(leaveRequest("  Moved  ")).toEqual({ reason: "Moved", reason_shared: false });
    expect(leaveRequest(" ")).toEqual({ reason: null, reason_shared: false });
    // ADR-760 (6A): «Να το δει και το μέλος».
    expect(leaveRequest("Moved", true)).toEqual({ reason: "Moved", reason_shared: true });
  });
});

describe("renewableSubscriptions", () => {
  it("keeps running packages whose renewal is the member's choice", () => {
    const rows = [
      { id: "a", status: "active", auto_renew: true },
      { id: "b", status: "active", auto_renew: false },
      { id: "c", status: "active", auto_renew: null },
      { id: "d", status: "expired", auto_renew: true },
    ];
    expect(renewableSubscriptions(rows).map((row) => row.id)).toEqual(["a", "b"]);
  });
});
