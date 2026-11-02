import { cache } from "react";

import type { PublicSite, SiteFaqEntry } from "@/api/box-site";
import { apiOriginForProxy } from "@/lib/organization-slug-alias";

/**
 * The box's website (ADR-352..354, ADR-388): server read, language rules,
 * and the small pure helpers its pages share.
 */

/** The cookie that remembers a visitor's EL/EN choice on box websites. */
export const SITE_LANGUAGE_COOKIE = "palee_site_lang";

/** Server read of a box's website; null when the box has none (or it fails: the box page still renders). */
export const loadPublicSite = cache(async (slug: string): Promise<PublicSite | null> => {
  try {
    const response = await fetch(`${apiOriginForProxy()}/api/public/sites/${encodeURIComponent(slug)}`, {
      headers: { accept: "application/json" },
      next: { revalidate: 60 },
    });
    if (!response.ok) return null;
    return (await response.json()) as PublicSite;
  } catch {
    return null;
  }
});

/** The first language of an Accept-Language header, as a lowercase base tag ("el", "en"). */
export function preferredLanguage(acceptLanguage: string | null | undefined): string | null {
  const first = acceptLanguage?.split(",")[0]?.split(";")[0]?.trim();
  if (!first || first === "*") return null;
  return first.split("-")[0]!.toLowerCase();
}

/**
 * ADR-388: whether a visit to the box-language page should go to `/en`.
 * Only a first visit (no choice remembered, no app language chosen) whose
 * browser prefers another language than the box's; English boxes never redirect.
 */
export function shouldOpenEnglish({
  boxLanguage,
  acceptLanguage,
  siteChoice,
  appLocaleChosen,
}: {
  boxLanguage: string;
  acceptLanguage: string | null | undefined;
  siteChoice: string | null | undefined;
  appLocaleChosen: boolean;
}) {
  if (boxLanguage === "en" || siteChoice || appLocaleChosen) return false;
  const preferred = preferredLanguage(acceptLanguage);
  return preferred !== null && preferred !== boxLanguage;
}

export type SiteLanguage = "box" | "en";

/** A box text in the page's language: the English version on `/en` when the box wrote one. */
export function siteText(language: SiteLanguage, original: string | null | undefined, english: string | null | undefined) {
  if (language === "en" && english && english.trim()) return english;
  return original ?? "";
}

/** FAQ entries in the page's language (ADR-388: both English halves, else the original). */
export function faqFor(language: SiteLanguage, entries: SiteFaqEntry[]) {
  return entries.map((entry) =>
    language === "en" && entry.question_en && entry.answer_en
      ? { question: entry.question_en, answer: entry.answer_en }
      : { question: entry.question, answer: entry.answer },
  );
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
