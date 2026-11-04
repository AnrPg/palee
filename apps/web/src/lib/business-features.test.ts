import { describe, expect, it } from "vitest";

import { featureOn, featuresSettled, showsWork } from "./business-features";

describe("business features (ADR-470)", () => {
  const ready = { status: "ready" as const, features: { referrals: true, card_autopay: false } };

  it("reads a feature from the answer", () => {
    expect(featureOn(ready, "referrals")).toBe(true);
    expect(featureOn(ready, "card_autopay")).toBe(false);
    expect(featureOn(ready, "promotions")).toBe(false);
  });

  it("hides while loading and shows when the answer cannot be read", () => {
    expect(featureOn({ status: "loading" }, "referrals")).toBe(false);
    expect(featureOn(null, "referrals")).toBe(false);
    expect(featureOn({ status: "error" }, "card_autopay")).toBe(true);
    expect(featuresSettled({ status: "loading" })).toBe(false);
    expect(featuresSettled(ready)).toBe(true);
  });

  it("keeps a work list while it still has rows", () => {
    expect(showsWork(ready, "card_autopay", 0)).toBe(false);
    expect(showsWork(ready, "card_autopay", 2)).toBe(true);
    expect(showsWork(ready, "referrals", 0)).toBe(true);
    expect(showsWork({ status: "loading" }, "card_autopay", undefined)).toBe(false);
  });
});
