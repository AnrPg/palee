import { describe, expect, it } from "vitest";

import { placementBlocked, placementBlockedCode, placementReasonKey } from "./class-placement";

describe("class placement (ADR-232)", () => {
  it("explains each booking refusal in staff words", () => {
    expect(placementReasonKey(null)).toBeNull();
    expect(placementReasonKey("slot_full")).toBe("placementReasonFull");
    expect(placementReasonKey("class_not_published")).toBe("placementReasonDraft");
    expect(placementReasonKey("finance_allowance_exhausted")).toBe("placementReasonNoVisits");
    // Any other package refusal reads as «the package does not cover it».
    expect(placementReasonKey("finance_capability_not_included")).toBe("placementReasonPackage");
    expect(placementReasonKey("something_new")).toBe("placementReasonOther");
  });

  it("lets a move use the visit of the booking it replaces", () => {
    const outOfVisits = { blocked_reason: "finance_allowance_exhausted" };
    expect(placementBlocked(outOfVisits, false)).toBe(true);
    expect(placementBlocked(outOfVisits, true)).toBe(false);
    expect(placementBlocked({ blocked_reason: "slot_full" }, true)).toBe(true);
    expect(placementBlocked({ blocked_reason: null }, false)).toBe(false);
  });

  it("offers a full class's waitlist to a new booking, never to a move (ADR-790)", () => {
    const full = { blocked_reason: null, waitlist: true };
    expect(placementBlocked(full, false)).toBe(false);
    expect(placementBlocked(full, true)).toBe(true);
    expect(placementBlockedCode(full, true)).toBe("slot_full");
    // The waitlist needs a visit left: a move's returned visit does not count.
    const spent = { blocked_reason: "finance_allowance_exhausted", waitlist: true };
    expect(placementBlocked(spent, false)).toBe(true);
    expect(placementBlockedCode(spent, false)).toBe("finance_allowance_exhausted");
  });
});
