import { describe, expect, it } from "vitest";

import { SUPPORTED_LOCALES } from "@/i18n/locales";

import { currentFirst, flagSrc, isRtlLanguage, languageShortCode, nativeLanguageName } from "./language-flags";

describe("language flags (ADR-545)", () => {
  it("gives every app language a flag, its code and its own name", () => {
    for (const locale of SUPPORTED_LOCALES) expect(flagSrc(locale)).toMatch(/^\/flags\/[a-z]{2}\.svg$/);
    expect(flagSrc("en")).toBe("/flags/gb.svg");
    expect(flagSrc("ar")).toBe("/flags/sa.svg");
    expect(flagSrc("pt-PT")).toBe("/flags/pt.svg");
    expect(flagSrc("he")).toBe("/flags/il.svg");
    expect(flagSrc("xx")).toBeNull();
    expect(languageShortCode("pt-PT")).toBe("PT");
    expect(nativeLanguageName("el")).toBe("Ελληνικά");
    expect(nativeLanguageName("ar")).toBe("العربية");
  });

  it("knows the right-to-left languages and lists the current one first", () => {
    expect(isRtlLanguage("ar")).toBe(true);
    expect(isRtlLanguage("he")).toBe(true);
    expect(isRtlLanguage("el")).toBe(false);
    expect(currentFirst(["en", "el", "de"], "de")).toEqual(["de", "en", "el"]);
    expect(currentFirst(["en", "el"], "fr")).toEqual(["en", "el"]);
  });
});
