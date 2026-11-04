import { describe, expect, it } from "vitest";

import {
  attribution,
  contactFields,
  preferredLanguage,
  preferredSiteLanguage,
  rememberedSiteLanguage,
  siteBasePath,
  siteLanguageCookie,
  siteLanguageFromSegment,
  siteLanguagePath,
  timetableByDay,
  translatedPage,
} from "./public-site";

// ADR-388: the box's language first, English on /en; the first visit follows the browser.
describe("website language", () => {
  it("reads the first Accept-Language tag as a base language", () => {
    expect(preferredLanguage("en-GB,en;q=0.9,el;q=0.8")).toBe("en");
    expect(preferredLanguage("*")).toBeNull();
    expect(preferredLanguage(null)).toBeNull();
  });

  it("opens a translation only on a first visit from another language", () => {
    const base = { boxLanguage: "el", languages: ["el", "en", "de"], siteChoice: null, appLocaleChosen: false };
    // ADR-520: the browser's language when the box shows it, English otherwise.
    expect(preferredSiteLanguage({ ...base, acceptLanguage: "de-DE" })).toBe("de");
    expect(preferredSiteLanguage({ ...base, acceptLanguage: "fr-FR" })).toBe("en");
    expect(preferredSiteLanguage({ ...base, languages: ["el", "de"], acceptLanguage: "fr" })).toBeNull();
    expect(preferredSiteLanguage({ ...base, acceptLanguage: "el-GR" })).toBeNull();
    expect(preferredSiteLanguage({ ...base, acceptLanguage: "de", siteChoice: "el" })).toBeNull();
    expect(preferredSiteLanguage({ ...base, acceptLanguage: "de", appLocaleChosen: true })).toBeNull();
    expect(preferredSiteLanguage({ ...base, boxLanguage: "en", languages: ["en"], acceptLanguage: "de" })).toBeNull();
  });

  it("names a translation by its path segment", () => {
    expect(siteLanguageFromSegment("pt-pt")).toBe("pt-PT");
    expect(siteLanguageFromSegment("EN")).toBe("en");
    expect(siteLanguageFromSegment("xx")).toBeNull();
    expect(siteLanguagePath("/b/kypseli", "pt-PT")).toBe("/b/kypseli/pt-pt");
    expect(siteLanguagePath("", "box")).toBe("/");
  });

  it("remembers the EL/EN choice per site", () => {
    const cookie = siteLanguageCookie("crossfit-kypseli", "en", true);
    expect(cookie).toContain("Secure");
    const value = cookie.split(";")[0]!.split("=")[1];
    expect(rememberedSiteLanguage(value, "crossfit-kypseli")).toBe("en");
    expect(rememberedSiteLanguage(value, "other-box")).toBeNull();
    expect(rememberedSiteLanguage(undefined, "crossfit-kypseli")).toBeNull();
  });

  it("puts the owner's translations into the box page and keeps the rest", () => {
    const page = {
      profile: { about: "Γεια", coaches: [{ id: "c", class_types: ["Αρχάριοι", "Yoga"] }] },
      rooms: [{ id: "r", name: "Αίθουσα", description: null, photos: [] }],
      locations: [{ id: "l", name: "Κυψέλη" }],
    } as unknown as Parameters<typeof translatedPage>[0];
    const site = {
      translation: "en",
      about: "Hello",
      texts: { "space:r:name": "Main room", "location:l:name": " " },
      class_type_names: { Αρχάριοι: "Beginners" },
    } as unknown as Parameters<typeof translatedPage>[1];
    const translated = translatedPage(page, site);
    expect(translated.profile.about).toBe("Hello");
    expect(translated.profile.coaches[0]!.class_types).toEqual(["Beginners", "Yoga"]);
    expect(translated.rooms[0]!.name).toBe("Main room");
    expect(translated.locations[0]!.name).toBe("Κυψέλη");
    expect(translatedPage(page, { ...site, translation: null })).toBe(page);
  });
});

describe("website forms", () => {
  it("sends «Κινητό ή email» as email or phone", () => {
    expect(contactFields(" eleni@example.com ")).toEqual({ email: "eleni@example.com" });
    expect(contactFields("6912345678")).toEqual({ phone: "6912345678" });
    expect(contactFields("  ")).toEqual({});
  });

  it("keeps UTM keys, the referrer host and the landing path only", () => {
    const result = attribution({ search: "?utm_source=ig&utm_campaign=spring&fbclid=x", pathname: "/b/kypseli" }, "https://www.instagram.com/p/1");
    expect(result).toEqual({ utm_source: "ig", utm_campaign: "spring", referrer_host: "www.instagram.com", landing_path: "/b/kypseli" });
    expect(attribution({ search: "", pathname: "/" }, "not a url")).toEqual({ landing_path: "/" });
  });

  it("serves the site from the domain root when standalone", () => {
    expect(siteBasePath("kypseli", true)).toBe("");
    expect(siteBasePath("kypseli", false)).toBe("/b/kypseli");
  });
});

describe("timetableByDay", () => {
  it("groups classes by the gym's day on a 24-hour clock", () => {
    const classes = [
      { id: "b", name: "WOD", scheduled_at: "2026-11-03T05:30:00Z", duration_minutes: 60, class_type_id: null, location_id: null },
      { id: "a", name: "Open gym", scheduled_at: "2026-11-02T22:30:00Z", duration_minutes: 90, class_type_id: null, location_id: null },
    ];
    const days = timetableByDay(classes, "Europe/Athens", "el");
    // 22:30 UTC on the 2nd is 00:30 on the 3rd in Athens: both on one day.
    expect(days).toHaveLength(1);
    expect(days[0]!.classes.map((entry) => [entry.id, entry.time])).toEqual([
      ["a", "00:30"],
      ["b", "07:30"],
    ]);
  });
});
