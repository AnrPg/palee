export const SUPPORTED_LOCALES = [
  "en",
  "el",
  "ar",
  "ru",
  "de",
  "es",
  "pt-PT",
  "he",
  "it",
  "bg",
  "nl",
  "fr",
] as const;

export type AppLocale = (typeof SUPPORTED_LOCALES)[number];

export const DEFAULT_LOCALE: AppLocale = "en";
export const LOCALE_COOKIE = "palee_locale";
export const RTL_LOCALES = new Set<AppLocale>(["ar", "he"]);

export const LOCALE_NAMES: Record<AppLocale, string> = {
  en: "English",
  el: "Ελληνικά",
  ar: "العربية",
  ru: "Русский",
  de: "Deutsch",
  es: "Español",
  "pt-PT": "Português",
  he: "עברית",
  it: "Italiano",
  bg: "Български",
  nl: "Nederlands",
  fr: "Français",
};

export function isAppLocale(value: string | null | undefined): value is AppLocale {
  return SUPPORTED_LOCALES.includes(value as AppLocale);
}

export function localeDirection(locale: AppLocale) {
  return RTL_LOCALES.has(locale) ? "rtl" : "ltr";
}

export function persistLocaleCookie(locale: AppLocale) {
  document.cookie = `${LOCALE_COOKIE}=${encodeURIComponent(locale)}; Path=/; Max-Age=31536000; SameSite=Lax`;
  document.documentElement.lang = locale;
  document.documentElement.dir = localeDirection(locale);
}

const LOCALE_RELOAD_KEY = "palee:locale-reload";

/**
 * Whether the page may reload once to show `locale` (the signed-in person's
 * language). A tab reloads for a given locale at most once, so a browser that
 * refuses the locale cookie, or rewrites the page, can never loop reloads.
 * Without session storage, no reload: the page stays in its language.
 */
export function claimLocaleReload(locale: AppLocale) {
  try {
    if (window.sessionStorage.getItem(LOCALE_RELOAD_KEY) === locale) return false;
    window.sessionStorage.setItem(LOCALE_RELOAD_KEY, locale);
    return true;
  } catch {
    return false;
  }
}

/** The page is in the person's language: a later language change may reload again. */
export function forgetLocaleReload() {
  try {
    window.sessionStorage.removeItem(LOCALE_RELOAD_KEY);
  } catch {}
}
