import { isAppLocale, LOCALE_NAMES } from "@/i18n/locales";

/**
 * ADR-545: one flag per language, the country the language comes from, the
 * same for everyone (EN 🇬🇧, AR 🇸🇦, PT 🇵🇹). Flags are SVGs in
 * public/flags (flag-icons, MIT), not emoji: Windows shows flag emoji as two
 * letters.
 */
const FLAG_COUNTRIES: Record<string, string> = {
  en: "gb",
  el: "gr",
  ar: "sa",
  ru: "ru",
  de: "de",
  es: "es",
  pt: "pt",
  he: "il",
  it: "it",
  bg: "bg",
  nl: "nl",
  fr: "fr",
};

function baseLanguage(code: string) {
  return code.split("-")[0].toLowerCase();
}

/** The flag image of a language, or null when it has none. */
export function flagSrc(code: string): string | null {
  const country = FLAG_COUNTRIES[baseLanguage(code)];
  return country ? `/flags/${country}.svg` : null;
}

/** The ISO 639-1 code shown next to the flag: «EL», «PT». */
export function languageShortCode(code: string) {
  return baseLanguage(code).toUpperCase();
}

/** The language's name in its own script: «Ελληνικά», «العربية». */
export function nativeLanguageName(code: string) {
  return isAppLocale(code) ? LOCALE_NAMES[code] : languageShortCode(code);
}

/** Languages written right to left. */
export function isRtlLanguage(code: string) {
  const base = baseLanguage(code);
  return base === "ar" || base === "he";
}

/** The text direction of a language's name. */
export function languageDir(code: string): "rtl" | "ltr" {
  return isRtlLanguage(code) ? "rtl" : "ltr";
}

/** The current language first, then the others in their given order. */
export function currentFirst<T extends string>(codes: readonly T[], current: string): T[] {
  const first = codes.filter((code) => code === current);
  return [...first, ...codes.filter((code) => code !== current)];
}
