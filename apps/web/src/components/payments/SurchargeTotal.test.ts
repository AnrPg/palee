import { describe, expect, it } from "vitest";

import { payableCents, surchargeShown, type MemberSurcharge } from "./SurchargeTotal";

const surcharge = (patch: Partial<MemberSurcharge> = {}): MemberSurcharge => ({
  applies: true,
  surcharge_cents: 90,
  total_cents: 6090,
  percent_bps: 150,
  fixed_cents: 0,
  reason: null,
  ...patch,
});

describe("member checkout surcharge line", () => {
  it("shows the line when the box surcharges online, also as «Χωρίς επιβάρυνση»", () => {
    expect(surchargeShown(surcharge())).toBe(true);
    expect(surchargeShown(surcharge({ applies: false, surcharge_cents: 0, reason: "card_unknown" }))).toBe(true);
  });

  it("hides it when the box adds nothing online", () => {
    expect(surchargeShown(surcharge({ applies: false, reason: "off" }))).toBe(false);
    expect(surchargeShown(surcharge({ applies: false, reason: "channel_off" }))).toBe(false);
    expect(surchargeShown(surcharge({ applies: false, reason: "not_allowed_here" }))).toBe(false);
    expect(surchargeShown(null)).toBe(false);
  });

  it("adds the surcharge to the amount only when it applies", () => {
    expect(payableCents(6000, surcharge())).toBe(6090);
    expect(payableCents(6000, surcharge({ applies: false }))).toBe(6000);
    expect(payableCents(6000, undefined)).toBe(6000);
  });
});
