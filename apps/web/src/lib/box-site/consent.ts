// ADR-354: consent before any of the box's tags on its website. Pure, so the
// banner, the tag loader and the tests share one set of rules.

export type ConsentCategory = "analytics" | "marketing";
export type ConsentChoice = { analytics: boolean; marketing: boolean };
export type TagKey = "ga4_measurement_id" | "meta_pixel_id" | "gtm_container_id";
export type SiteTags = Record<TagKey, string | null>;

/** What the site remembers in its first-party cookie (strictly necessary). */
export type StoredConsent = ConsentChoice & {
  visitorId: string;
  bannerVersion: number;
  expiresAt: string;
};

export const CONSENT_COOKIE = "palee_site_consent";

export const NO_CONSENT: ConsentChoice = { analytics: false, marketing: false };

/** The choice that still holds now, or null when the banner must ask (again). */
export function currentChoice(stored: StoredConsent | null, bannerVersion: number, now: Date): ConsentChoice | null {
  if (!stored) return null;
  if (stored.bannerVersion !== bannerVersion) return null;
  if (new Date(stored.expiresAt).getTime() <= now.getTime()) return null;
  return { analytics: stored.analytics, marketing: stored.marketing };
}

/** No tags, no banner: Palee itself sets no tracking cookie. */
export function bannerNeeded(tags: SiteTags, stored: StoredConsent | null, bannerVersion: number, now: Date) {
  return hasTags(tags) && currentChoice(stored, bannerVersion, now) === null;
}

export function hasTags(tags: SiteTags) {
  return Object.values(tags).some((value) => value !== null && value !== "");
}

/** GA4 with analytics, the Meta Pixel with marketing, GTM with either (same rule as the API). */
export function allowedTags(tags: SiteTags, choice: ConsentChoice): TagKey[] {
  const rules: [TagKey, boolean][] = [
    ["ga4_measurement_id", choice.analytics],
    ["meta_pixel_id", choice.marketing],
    ["gtm_container_id", choice.analytics || choice.marketing],
  ];
  return rules.filter(([key, allowed]) => allowed && Boolean(tags[key])).map(([key]) => key);
}

type ConsentModeValue = "granted" | "denied";

/**
 * Google Consent Mode v2 signals. `default` is pushed before GTM loads
 * (everything denied); `update` follows the visitor's choice.
 */
export function consentModeDefault(): Record<string, ConsentModeValue | number> {
  return {
    ad_storage: "denied",
    ad_user_data: "denied",
    ad_personalization: "denied",
    analytics_storage: "denied",
    functionality_storage: "denied",
    personalization_storage: "denied",
    security_storage: "granted",
    wait_for_update: 500,
  };
}

export function consentModeUpdate(choice: ConsentChoice): Record<string, ConsentModeValue> {
  const value = (granted: boolean): ConsentModeValue => (granted ? "granted" : "denied");
  return {
    ad_storage: value(choice.marketing),
    ad_user_data: value(choice.marketing),
    ad_personalization: value(choice.marketing),
    analytics_storage: value(choice.analytics),
  };
}

export type ConsentAction = "accept_all" | "reject_all" | "custom" | "withdraw";

/** The choice an action records (reject and withdraw are all off). */
export function choiceFor(action: ConsentAction, custom: ConsentChoice = NO_CONSENT): ConsentChoice {
  switch (action) {
    case "accept_all":
      return { analytics: true, marketing: true };
    case "custom":
      return { ...custom };
    default:
      return { ...NO_CONSENT };
  }
}

/** Cookie value: compact JSON, URI-encoded. Invalid values read as "no choice". */
export function encodeConsent(consent: StoredConsent) {
  return encodeURIComponent(
    JSON.stringify({ v: consent.visitorId, b: consent.bannerVersion, a: consent.analytics, m: consent.marketing, e: consent.expiresAt }),
  );
}

export function decodeConsent(raw: string | undefined | null): StoredConsent | null {
  if (!raw) return null;
  try {
    const value = JSON.parse(decodeURIComponent(raw)) as Record<string, unknown>;
    if (
      typeof value.v !== "string" ||
      typeof value.b !== "number" ||
      typeof value.a !== "boolean" ||
      typeof value.m !== "boolean" ||
      typeof value.e !== "string"
    ) {
      return null;
    }
    return { visitorId: value.v, bannerVersion: value.b, analytics: value.a, marketing: value.m, expiresAt: value.e };
  } catch {
    return null;
  }
}
