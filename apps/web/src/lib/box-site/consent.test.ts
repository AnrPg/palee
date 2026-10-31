import { describe, expect, it } from "vitest";

import {
  allowedTags,
  bannerNeeded,
  choiceFor,
  consentModeDefault,
  consentModeUpdate,
  currentChoice,
  decodeConsent,
  encodeConsent,
  type SiteTags,
  type StoredConsent,
} from "./consent";

const now = new Date("2026-11-02T10:00:00Z");
const tags: SiteTags = { meta_pixel_id: "123456789", ga4_measurement_id: "G-ABCD1234", gtm_container_id: null };
const stored: StoredConsent = {
  visitorId: "6f1c5a9e-6c0e-4c8e-9d3a-4b8f0b9c1a2d",
  bannerVersion: 2,
  analytics: true,
  marketing: false,
  expiresAt: "2027-05-01T00:00:00Z",
};

describe("box site consent (ADR-354)", () => {
  it("asks only when the box has tags and there is no valid choice", () => {
    expect(bannerNeeded({ meta_pixel_id: null, ga4_measurement_id: null, gtm_container_id: null }, null, 1, now)).toBe(false);
    expect(bannerNeeded(tags, null, 2, now)).toBe(true);
    expect(bannerNeeded(tags, stored, 2, now)).toBe(false);
    // A new tag (banner version) or an expired choice asks again.
    expect(bannerNeeded(tags, stored, 3, now)).toBe(true);
    expect(bannerNeeded(tags, { ...stored, expiresAt: "2026-11-01T00:00:00Z" }, 2, now)).toBe(true);
    expect(currentChoice(stored, 2, now)).toEqual({ analytics: true, marketing: false });
  });

  it("loads each tag only with its category; nothing without consent", () => {
    expect(allowedTags(tags, { analytics: true, marketing: false })).toEqual(["ga4_measurement_id"]);
    expect(allowedTags(tags, { analytics: false, marketing: true })).toEqual(["meta_pixel_id"]);
    expect(allowedTags(tags, { analytics: false, marketing: false })).toEqual([]);
    expect(allowedTags({ ...tags, gtm_container_id: "GTM-AAAA" }, { analytics: false, marketing: true })).toEqual([
      "meta_pixel_id",
      "gtm_container_id",
    ]);
  });

  it("accept and reject are symmetric; custom keeps the toggles", () => {
    expect(choiceFor("accept_all")).toEqual({ analytics: true, marketing: true });
    expect(choiceFor("reject_all", { analytics: true, marketing: true })).toEqual({ analytics: false, marketing: false });
    expect(choiceFor("withdraw")).toEqual({ analytics: false, marketing: false });
    expect(choiceFor("custom", { analytics: true, marketing: false })).toEqual({ analytics: true, marketing: false });
  });

  it("Consent Mode v2 starts denied and follows the choice", () => {
    const defaults = consentModeDefault();
    expect(defaults.ad_storage).toBe("denied");
    expect(defaults.analytics_storage).toBe("denied");
    expect(consentModeUpdate({ analytics: true, marketing: false })).toEqual({
      ad_storage: "denied",
      ad_user_data: "denied",
      ad_personalization: "denied",
      analytics_storage: "granted",
    });
  });

  it("round-trips the cookie and treats garbage as no choice", () => {
    expect(decodeConsent(encodeConsent(stored))).toEqual(stored);
    expect(decodeConsent("not json")).toBeNull();
    expect(decodeConsent(encodeURIComponent(JSON.stringify({ v: 1 })))).toBeNull();
    expect(decodeConsent(undefined)).toBeNull();
  });
});
