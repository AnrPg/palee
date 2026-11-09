import { describe, expect, it } from "vitest";

import { nearbyEyebrow } from "./nearby";

describe("nearbyEyebrow (ADR-583)", () => {
  it("keeps «Κοντά μου» within the person's radius or without an answer", () => {
    expect(nearbyEyebrow(undefined)).toEqual({ key: "nearMe" });
    expect(nearbyEyebrow({ scope: "radius", radius_km: 5, town: null, widened: false })).toEqual({ key: "nearMe" });
  });

  it("names the wider radius the list came from", () => {
    expect(nearbyEyebrow({ scope: "radius", radius_km: 25, town: null, widened: true })).toEqual({ key: "nearUpTo", km: 25 });
  });

  it("names the town when the list fell back to it", () => {
    expect(nearbyEyebrow({ scope: "town", radius_km: null, town: "Βόλος", widened: true })).toEqual({ key: "nearInTown", town: "Βόλος" });
  });
});
