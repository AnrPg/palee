import { describe, expect, it } from "vitest";

import { allowedTags, CONSENT_DEFAULT, consentAction, consentCategories, consentCookie, consentModeUpdate, readConsent } from "./site-consent";

const TAGS = { ga4_measurement_id: "G-1", gtm_container_id: "GTM-1", meta_pixel_id: "123" };

// ADR-354, ANR s4 A: nothing before a choice; GTM with Στατιστικά OR Marketing; Consent Mode denied by default.
describe("site consent", () => {
  it("loads GTM with either category and the others only with their own", () => {
    expect(allowedTags(TAGS, { analytics: false, marketing: false })).toEqual([]);
    expect(allowedTags(TAGS, { analytics: true, marketing: false })).toEqual(["ga4_measurement_id", "gtm_container_id"]);
    expect(allowedTags(TAGS, { analytics: false, marketing: true })).toEqual(["gtm_container_id", "meta_pixel_id"]);
  });

  it("starts every Consent Mode signal denied and grants per choice", () => {
    expect(Object.values(CONSENT_DEFAULT).every((value) => value === "denied")).toBe(true);
    expect(consentModeUpdate({ analytics: true, marketing: false })).toEqual({
      ad_storage: "denied",
      ad_user_data: "denied",
      ad_personalization: "denied",
      analytics_storage: "granted",
    });
  });

  it("round-trips a stored choice and drops it when expired or the banner changed", () => {
    const stored = { analytics: true, marketing: false, version: 2, visitorId: "v-1", expiresAt: Date.now() + 60_000 };
    const cookie = consentCookie("kypseli", stored, false).split(";")[0]!;
    expect(readConsent(cookie, "kypseli", 2, Date.now())).toEqual(stored);
    expect(readConsent(cookie, "kypseli", 3, Date.now())).toBeNull();
    expect(readConsent(cookie, "kypseli", 2, stored.expiresAt + 1)).toBeNull();
    expect(readConsent("other=1", "kypseli", 2, Date.now())).toBeNull();
  });

  it("logs the action of a choice", () => {
    expect(consentAction({ analytics: true, marketing: true }, false)).toBe("accept_all");
    expect(consentAction({ analytics: false, marketing: false }, false)).toBe("reject_all");
    expect(consentAction({ analytics: false, marketing: false }, true)).toBe("withdraw");
    expect(consentAction({ analytics: true, marketing: false }, false)).toBe("custom");
  });

  it("asks only about categories the box has a tag for", () => {
    expect(consentCategories({ ga4_measurement_id: "G-1", gtm_container_id: null, meta_pixel_id: null })).toEqual({ analytics: true, marketing: false });
  });
});
