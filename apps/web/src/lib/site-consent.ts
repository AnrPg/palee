import type { PublicSite } from "@/api/box-site";

/**
 * Cookie consent on a box's website (ADR-354, ANR s4 A). Nothing of the
 * box's tags loads before a choice; GTM loads after «Στατιστικά» OR
 * «Marketing», with every Google Consent Mode signal defaulting to denied.
 * The choice lasts the box's validity (6 months) and is asked again when the
 * box adds a tag (a new banner version).
 */

export type SiteTags = PublicSite["tracking"]["tags"];
export type ConsentChoice = { analytics: boolean; marketing: boolean };
export type StoredConsent = ConsentChoice & { version: number; visitorId: string; expiresAt: number };
export type TagKey = "ga4_measurement_id" | "gtm_container_id" | "meta_pixel_id";

const COOKIE_PREFIX = "palee_site_consent_";

export function consentCookieName(slug: string) {
  return COOKIE_PREFIX + slug.replace(/[^a-z0-9-]/gi, "").slice(0, 60);
}

/** The visitor's stored choice for this site, or null when there is none, it expired or the banner changed. */
export function readConsent(cookies: string, slug: string, bannerVersion: number, now: number): StoredConsent | null {
  const name = consentCookieName(slug);
  const raw = cookies
    .split(";")
    .map((part) => part.trim())
    .find((part) => part.startsWith(`${name}=`))
    ?.slice(name.length + 1);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(decodeURIComponent(raw)) as Partial<{ v: number; a: boolean; m: boolean; id: string; exp: number }>;
    if (parsed.v !== bannerVersion || typeof parsed.exp !== "number" || parsed.exp <= now || typeof parsed.id !== "string") return null;
    return { analytics: parsed.a === true, marketing: parsed.m === true, version: parsed.v, visitorId: parsed.id, expiresAt: parsed.exp };
  } catch {
    return null;
  }
}

/** The cookie that remembers a choice (first-party, strictly necessary: it only remembers the choice). */
export function consentCookie(slug: string, consent: StoredConsent, secure: boolean) {
  const value = encodeURIComponent(
    JSON.stringify({ v: consent.version, a: consent.analytics, m: consent.marketing, id: consent.visitorId, exp: consent.expiresAt }),
  );
  const maxAge = Math.max(0, Math.floor((consent.expiresAt - Date.now()) / 1000));
  return `${consentCookieName(slug)}=${value}; Path=/; Max-Age=${maxAge}; SameSite=Lax${secure ? "; Secure" : ""}`;
}

/** Which of the box's tags a choice allows (GTM with either category). */
export function allowedTags(tags: SiteTags, choice: ConsentChoice): TagKey[] {
  const allowed: TagKey[] = [];
  if (tags.ga4_measurement_id && choice.analytics) allowed.push("ga4_measurement_id");
  if (tags.gtm_container_id && (choice.analytics || choice.marketing)) allowed.push("gtm_container_id");
  if (tags.meta_pixel_id && choice.marketing) allowed.push("meta_pixel_id");
  return allowed;
}

/** Google Consent Mode v2: the default (everything denied) and the update for a choice. */
export const CONSENT_DEFAULT = {
  ad_storage: "denied",
  ad_user_data: "denied",
  ad_personalization: "denied",
  analytics_storage: "denied",
} as const;

export function consentModeUpdate(choice: ConsentChoice) {
  const marketing = choice.marketing ? "granted" : "denied";
  return {
    ad_storage: marketing,
    ad_user_data: marketing,
    ad_personalization: marketing,
    analytics_storage: choice.analytics ? "granted" : "denied",
  };
}

/** The action the consent log records for a choice. */
export function consentAction(choice: ConsentChoice, withdrawing: boolean) {
  if (withdrawing && !choice.analytics && !choice.marketing) return "withdraw" as const;
  if (choice.analytics && choice.marketing) return "accept_all" as const;
  if (!choice.analytics && !choice.marketing) return "reject_all" as const;
  return "custom" as const;
}

/** Which categories the banner asks about: only those the box has a tag for. */
export function consentCategories(tags: SiteTags) {
  return {
    analytics: Boolean(tags.ga4_measurement_id || tags.gtm_container_id),
    marketing: Boolean(tags.meta_pixel_id || tags.gtm_container_id),
  };
}
