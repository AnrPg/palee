import { describe, expect, it } from "vitest";

import type { SurchargeLaw, SurchargeQuote, SurchargeStatus } from "@/api/card-surcharge";

import {
  DEFAULT_CHANNELS,
  NON_EEA_COUNTRY,
  asksCardKind,
  deskCard,
  deskCardKinds,
  enableBody,
  fieldForSurchargeError,
  initialDraft,
  lawSentence,
  parseFixedCents,
  parsePercentBps,
  stepErrors,
  surchargeOn,
  type GuideDraft,
} from "./card-surcharge";

const law = (patch: Partial<SurchargeLaw> = {}) => ({ rule: "eea_non_consumer", cap_bps: null, at_cost: true, region_required: false, ...patch }) as SurchargeLaw;
const draft = (patch: Partial<GuideDraft> = {}): GuideDraft => ({ percent: "1,5", fixed: "", channels: ["online"], atCost: true, ...patch });
const quote = (patch: Partial<SurchargeQuote>) => ({ rule: "eea_non_consumer", reason: null, ...patch }) as SurchargeQuote;

describe("card surcharge guide", () => {
  it("parses percent and fixed amounts in either decimal mark", () => {
    expect(parsePercentBps("1,5")).toBe(150);
    expect(parsePercentBps("2.25%")).toBe(225);
    expect(parsePercentBps("")).toBe(0);
    expect(parsePercentBps("abc")).toBeNull();
    expect(parseFixedCents("0,30 €")).toBe(30);
    expect(parseFixedCents("")).toBe(0);
    expect(parseFixedCents("-1")).toBeNull();
  });

  it("starts a box that never saved with the POS off", () => {
    const status = { saved: false, settings: { percent_bps: 0, fixed_cents: 0, channels: [], at_cost_confirmed: false } } as unknown as SurchargeStatus;
    expect(initialDraft(status, "el").channels).toEqual(DEFAULT_CHANNELS);
    expect(DEFAULT_CHANNELS).not.toContain("desk");
  });

  it("keeps the amount step's errors under their fields", () => {
    expect(stepErrors(1, draft(), law())).toEqual({});
    expect(stepErrors(1, draft({ percent: "" }), law())).toEqual({ percent: "errorPercentRequired" });
    expect(stepErrors(1, draft({ percent: "", fixed: "0,20" }), law())).toEqual({});
    expect(stepErrors(1, draft({ percent: "3" }), law({ cap_bps: 200 }))).toEqual({ percent: "errorAboveCap" });
    expect(stepErrors(1, draft({ atCost: false }), law())).toEqual({ atCost: "errorAtCostRequired" });
    expect(stepErrors(1, draft({ fixed: "x" }), law()).fixed).toBe("errorFixedInvalid");
    expect(stepErrors(2, draft({ channels: [] }), law())).toEqual({ channels: "errorChannelsRequired" });
  });

  it("turns the surcharge on with the guide's answers in channel order", () => {
    expect(enableBody(draft({ channels: ["desk", "online"], fixed: "0,10" }))).toEqual({
      enabled: true,
      percent_bps: 150,
      fixed_cents: 10,
      channels: ["online", "desk"],
      at_cost_confirmed: true,
    });
  });

  it("rounds the surcharge half up before adding the fixed amount", () => {
    expect(surchargeOn(6000, 150, 0)).toBe(90);
    expect(surchargeOn(3333, 150, 10)).toBe(60);
  });

  it("puts the API's refusal under the field it is about", () => {
    expect(fieldForSurchargeError({ code: "card_surcharge_not_allowed", error: "", params: { reason: "above_cap" } })).toBe("percent");
    expect(fieldForSurchargeError({ code: "validation_failed", error: "", errors: { channels: ["empty"] } })).toBe("channels");
    expect(fieldForSurchargeError({ code: "validation_failed", error: "", errors: { region_code: ["unknown"] } })).toBe("region");
    expect(fieldForSurchargeError(undefined)).toBeNull();
  });

  it("says the law in one sentence", () => {
    expect(lawSentence(law(), "el").key).toBe("lawEeaNonConsumer");
    expect(lawSentence(law({ rule: "credit_only", cap_bps: 300 }), "en")).toEqual({ key: "lawCreditOnly", values: { cap: "3%" } });
    expect(lawSentence(law({ region_required: true }), "en").key).toBe("lawRegionRequired");
  });
});

describe("«Κάρτα στο POS»", () => {
  it("asks for the card only when the kind changes the surcharge", () => {
    expect(asksCardKind(quote({ reason: "card_unknown" }))).toBe(true);
    expect(asksCardKind(quote({ reason: "off" }))).toBe(false);
    expect(asksCardKind(quote({ reason: "channel_off" }))).toBe(false);
    expect(asksCardKind(quote({ rule: "any", reason: null }))).toBe(false);
    expect(asksCardKind(null)).toBe(false);
  });

  it("offers the answers the law reads, «Δεν ξέρω» last", () => {
    expect(deskCardKinds("eea_non_consumer")).toEqual(["consumer_eea", "business", "non_eea", "unknown"]);
    expect(deskCardKinds("credit_only").at(-1)).toBe("unknown");
    expect(deskCardKinds("none")).toEqual([]);
  });

  it("sends only what staff know about the card", () => {
    expect(deskCard("business")).toEqual({ commercial: true });
    expect(deskCard("non_eea")).toEqual({ country: NON_EEA_COUNTRY });
    expect(deskCard("credit")).toEqual({ funding: "credit" });
    expect(deskCard("unknown")).toEqual({});
  });
});
