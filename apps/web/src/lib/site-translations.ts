import type { SiteLanguages, SiteTranslationItem, SiteTranslationStatus } from "@/api/box-site";
import { isAppLocale, LOCALE_NAMES, type AppLocale } from "@/i18n/locales";

/**
 * «Μεταφράσεις» of the box's website (ADR-500): pure helpers for the
 * languages card, the side-by-side list and the one-at-a-time view.
 */

export type TranslationFilter = "todo" | "missing" | "stale" | "machine" | "all";

export const TRANSLATION_FILTERS: TranslationFilter[] = ["todo", "missing", "stale", "machine", "all"];

/** The groups in the website's order (matches the API's `group`). */
export const TRANSLATION_GROUPS = ["about", "rooms", "faq", "packages", "classes", "events", "locations"] as const;
export type TranslationGroup = (typeof TRANSLATION_GROUPS)[number];

/** Whether an item needs the owner (missing, out of date, or a machine text nobody checked). */
export function needsWork(status: SiteTranslationStatus) {
  return status !== "ok";
}

export function matchesFilter(item: Pick<SiteTranslationItem, "status">, filter: TranslationFilter) {
  if (filter === "all") return true;
  if (filter === "todo") return needsWork(item.status);
  return item.status === filter;
}

/** The items of a filter, grouped in the website's order; empty groups left out. */
export function groupItems<T extends Pick<SiteTranslationItem, "group" | "status">>(items: T[], filter: TranslationFilter) {
  const shown = items.filter((item) => matchesFilter(item, filter));
  return TRANSLATION_GROUPS.map((group) => ({ group, items: shown.filter((item) => item.group === group) })).filter((entry) => entry.items.length > 0);
}

export type StatusCounts = Record<SiteTranslationStatus, number>;

/** How many items each filter would show. */
export function filterCounts(counts: StatusCounts, total: number): Record<TranslationFilter, number> {
  return {
    todo: counts.missing + counts.stale + counts.machine,
    missing: counts.missing,
    stale: counts.stale,
    machine: counts.machine,
    all: total,
  };
}

/** Share of texts that are translated and checked, 0–100 (100 when there is nothing to translate). */
export function readyPercent(counts: StatusCounts, total: number) {
  if (total <= 0) return 100;
  return Math.round((counts.ok / total) * 100);
}

/** Texts a machine may (re)write: missing or out of date. */
export function machineDue(counts: StatusCounts) {
  return counts.missing + counts.stale;
}

/** A language's own name ("Deutsch"), whatever the reader's language. */
export function languageName(locale: string) {
  return isAppLocale(locale) ? LOCALE_NAMES[locale as AppLocale] : locale;
}

/** The progress of one language, or an empty one when it was never counted (just added). */
export function progressFor(languages: SiteLanguages, locale: string) {
  const found = languages.progress.find((entry) => entry.locale === locale);
  const total = found?.total ?? languages.progress[0]?.total ?? 0;
  const counts: StatusCounts = found?.counts ?? { missing: total, stale: 0, machine: 0, ok: 0 };
  return { counts, total };
}

/** The languages the owner can still add. */
export function addableLanguages(languages: SiteLanguages, chosen: string[]) {
  return languages.available.filter((locale) => !chosen.includes(locale));
}

/** Adds a language (hidden until the owner shows it). */
export function addLanguage(state: { translation_locales: string[]; visible_locales: string[] }, locale: string) {
  if (state.translation_locales.includes(locale)) return state;
  return { ...state, translation_locales: [...state.translation_locales, locale] };
}

/** Removes a language; its translations stay saved, so adding it back restores them. */
export function removeLanguage(state: { translation_locales: string[]; visible_locales: string[] }, locale: string) {
  return {
    translation_locales: state.translation_locales.filter((entry) => entry !== locale),
    visible_locales: state.visible_locales.filter((entry) => entry !== locale),
  };
}

/** Shows or hides a language on the website. */
export function showLanguage(state: { translation_locales: string[]; visible_locales: string[] }, locale: string, visible: boolean) {
  const others = state.visible_locales.filter((entry) => entry !== locale);
  return {
    ...state,
    visible_locales: visible ? state.translation_locales.filter((entry) => entry === locale || others.includes(entry)) : others,
  };
}

/** The queue of the one-at-a-time view: what still needs the owner, in the website's order. */
export function workQueue<T extends Pick<SiteTranslationItem, "group" | "status">>(items: T[]) {
  return groupItems(items, "todo").flatMap((entry) => entry.items);
}

/** Where the owner changes the box's own text of an item (staff app path, before the org prefix). */
export function sourceEditPath(item: Pick<SiteTranslationItem, "group" | "id">) {
  switch (item.group) {
    case "about":
      return "/admin/public-page";
    case "rooms":
      return "/admin/spaces";
    case "faq":
      return "/admin/settings/website";
    case "packages":
      return `/admin/finance/packages/${item.id}`;
    case "classes":
      return "/admin/class-schedule";
    case "events":
      return `/admin/community/events/${item.id}`;
    case "locations":
      return `/admin/settings/locations/${item.id}`;
    default:
      return "/admin/settings/website";
  }
}

/** A text of the public site in the visitor's language: the translation when there is one. */
export function siteTextFor(texts: Record<string, string> | null | undefined, kind: string, id: string, field: string, original: string | null | undefined) {
  const translated = texts?.[`${kind}:${id}:${field}`];
  return translated && translated.trim() ? translated : original ?? "";
}
