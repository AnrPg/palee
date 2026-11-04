import { cache } from "react";

import type { PublicSite } from "@/api/box-site";
import type { PublicBoxPage } from "@/api/social";
import { SUPPORTED_LOCALES } from "@/i18n/locales";
import { apiOriginForProxy } from "@/lib/organization-slug-alias";
import { siteTextFor } from "@/lib/site-translations";

/**
 * The box's website (ADR-352..354, ADR-388): server read, language rules,
 * and the small pure helpers its pages share.
 */

/** The cookie that remembers a visitor's language choice on box websites. */
export const SITE_LANGUAGE_COOKIE = "palee_site_lang";

/**
 * Server read of a box's website, in one of its translations when `lang` is
 * given (ADR-500); null when the box has none (or it fails: the box page
 * still renders).
 */
export const loadPublicSite = cache(async (slug: string, lang?: string | null): Promise<PublicSite | null> => {
  try {
    const query = lang ? `?lang=${encodeURIComponent(lang)}` : "";
    const response = await fetch(`${apiOriginForProxy()}/api/public/sites/${encodeURIComponent(slug)}${query}`, {
      headers: { accept: "application/json" },
      next: { revalidate: 60 },
    });
    if (!response.ok) return null;
    return (await response.json()) as PublicSite;
  } catch {
    return null;
  }
});

/** The remembered choice for this site ("<slug>:<code>"), or null. */
export function rememberedSiteLanguage(cookieValue: string | undefined, slug: string): string | null {
  if (!cookieValue) return null;
  const [owner, code] = decodeURIComponent(cookieValue).split(":");
  return owner === slug && code ? code : null;
}

/** The cookie that remembers a visitor's language choice for one site. */
export function siteLanguageCookie(slug: string, code: string, secure: boolean) {
  return `${SITE_LANGUAGE_COOKIE}=${encodeURIComponent(`${slug}:${code}`)}; Path=/; Max-Age=31536000; SameSite=Lax${secure ? "; Secure" : ""}`;
}

/** Remembers the visitor's choice in the browser (the switch's links then reload the page). */
export function rememberSiteLanguage(slug: string, code: string) {
  document.cookie = siteLanguageCookie(slug, code, window.location.protocol === "https:");
}

/** The id of a form field's inline error. */
export function fieldErrorId(base: string, field: string) {
  return `${base}-${field}-error`;
}

/** The first language of an Accept-Language header, as a lowercase base tag ("el", "en"). */
export function preferredLanguage(acceptLanguage: string | null | undefined): string | null {
  const first = acceptLanguage?.split(",")[0]?.split(";")[0]?.trim();
  if (!first || first === "*") return null;
  return first.split("-")[0]!.toLowerCase();
}

/**
 * ADR-388/500: the translation a first visit to the box-language page goes
 * to, or null to stay. Only a first visit (no choice remembered, no app
 * language chosen) whose browser prefers another language than the box's:
 * that language when the box shows it, otherwise English when it does.
 */
export function preferredSiteLanguage({
  boxLanguage,
  languages,
  acceptLanguage,
  siteChoice,
  appLocaleChosen,
}: {
  boxLanguage: string;
  languages: string[];
  acceptLanguage: string | null | undefined;
  siteChoice: string | null | undefined;
  appLocaleChosen: boolean;
}): string | null {
  if (siteChoice || appLocaleChosen) return null;
  const preferred = preferredLanguage(acceptLanguage);
  if (preferred === null || preferred === baseLanguage(boxLanguage)) return null;
  const translations = languages.filter((code) => baseLanguage(code) !== baseLanguage(boxLanguage));
  return translations.find((code) => baseLanguage(code) === preferred) ?? translations.find((code) => code === "en") ?? null;
}

/** "box" for the box's own language, or a translation's code ("en", "de", "pt-PT"). */
export type SiteLanguage = "box" | (string & {});

function baseLanguage(code: string) {
  return code.split("-")[0]!.toLowerCase();
}

/** The app locale a path segment names ("pt-pt" → "pt-PT"), or null. */
export function siteLanguageFromSegment(segment: string | null | undefined): string | null {
  if (!segment) return null;
  const wanted = segment.toLowerCase();
  return SUPPORTED_LOCALES.find((code) => code.toLowerCase() === wanted) ?? null;
}

/** The path of the site in a language: the box's own at the base, a translation at `/<code>`. */
export function siteLanguagePath(basePath: string, language: SiteLanguage) {
  if (language === "box") return basePath || "/";
  return `${basePath}/${language.toLowerCase()}`;
}

/** The code a page's language stands for (the box's own for "box"). */
export function siteLanguageCode(language: SiteLanguage, boxLanguage: string) {
  return language === "box" ? boxLanguage : language;
}

/**
 * ADR-500: the box page with the owner's translations in it (about, rooms,
 * locations, the class names its coaches teach), so the sections render
 * as they are. The box's own text stays where nothing is translated.
 */
export function translatedPage(page: PublicBoxPage, site: PublicSite): PublicBoxPage {
  if (!site.translation) return page;
  const texts = site.texts ?? {};
  const names = site.class_type_names ?? {};
  return {
    ...page,
    profile: {
      ...page.profile,
      about: site.about?.trim() ? site.about : page.profile.about,
      coaches: page.profile.coaches.map((coach) => ({ ...coach, class_types: coach.class_types.map((name) => names[name] ?? name) })),
    },
    rooms: (page.rooms ?? []).map((room) => ({
      ...room,
      name: siteTextFor(texts, "space", room.id, "name", room.name),
      description: room.description ? siteTextFor(texts, "space", room.id, "description", room.description) : room.description,
    })),
    locations: page.locations.map((location) => ({ ...location, name: siteTextFor(texts, "location", location.id, "name", location.name) })),
  };
}

/** «Κινητό ή email» in one field: an address goes as `email`, anything else as `phone`. */
export function contactFields(value: string): { email?: string; phone?: string } {
  const trimmed = value.trim();
  if (!trimmed) return {};
  return trimmed.includes("@") ? { email: trimmed } : { phone: trimmed };
}

const UTM_KEYS = ["utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content"] as const;

/** ADR-353: where a form came from (UTM keys, the referrer's host, the landing path). Nothing else. */
export function attribution(location: { search: string; pathname: string }, referrer: string) {
  const params = new URLSearchParams(location.search);
  const result: Record<string, string> = {};
  for (const key of UTM_KEYS) {
    const value = params.get(key);
    if (value) result[key] = value.slice(0, 120);
  }
  try {
    if (referrer) result.referrer_host = new URL(referrer).host;
  } catch {
    // Not a URL: nothing to keep.
  }
  result.landing_path = location.pathname.slice(0, 200);
  return result;
}

/** The site's timetable grouped by the gym's day, in order. */
export function timetableByDay(
  classes: PublicSite["timetable"],
  timeZone: string,
  locale: string,
): { day: string; label: string; classes: { id: string; time: string; name: string; minutes: number }[] }[] {
  const dayKey = new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" });
  const dayLabel = new Intl.DateTimeFormat(locale, { timeZone, weekday: "long", day: "numeric", month: "numeric" });
  const time = new Intl.DateTimeFormat(locale, { timeZone, hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
  const days = new Map<string, { day: string; label: string; classes: { id: string; time: string; name: string; minutes: number }[] }>();
  for (const entry of [...classes].sort((a, b) => a.scheduled_at.localeCompare(b.scheduled_at))) {
    const at = new Date(entry.scheduled_at);
    const key = dayKey.format(at);
    const day = days.get(key) ?? { day: key, label: dayLabel.format(at), classes: [] };
    day.classes.push({ id: entry.id, time: time.format(at), name: entry.name, minutes: entry.duration_minutes });
    days.set(key, day);
  }
  return [...days.values()];
}

/** The address a visitor should use for the site: the custom host's root or `/b/<slug>`. */
export function siteBasePath(slug: string, standalone: boolean) {
  return standalone ? "" : `/b/${slug}`;
}
