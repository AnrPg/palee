import { describe, expect, it } from "vitest";

import {
  attribution,
  contactFields,
  faqFor,
  preferredLanguage,
  rememberedSiteLanguage,
  shouldOpenEnglish,
  siteBasePath,
  siteLanguageCookie,
  siteText,
  timetableByDay,
} from "./public-site";

// ADR-388: the box's language first, English on /en; the first visit follows the browser.
describe("website language", () => {
  it("reads the first Accept-Language tag as a base language", () => {
    expect(preferredLanguage("en-GB,en;q=0.9,el;q=0.8")).toBe("en");
    expect(preferredLanguage("*")).toBeNull();
    expect(preferredLanguage(null)).toBeNull();
  });

  it("opens English only on a first visit from another language", () => {
    const base = { boxLanguage: "el", siteChoice: null, appLocaleChosen: false };
    expect(shouldOpenEnglish({ ...base, acceptLanguage: "de-DE" })).toBe(true);
    expect(shouldOpenEnglish({ ...base, acceptLanguage: "el-GR" })).toBe(false);
    expect(shouldOpenEnglish({ ...base, acceptLanguage: "de", siteChoice: "el" })).toBe(false);
    expect(shouldOpenEnglish({ ...base, acceptLanguage: "de", appLocaleChosen: true })).toBe(false);
    expect(shouldOpenEnglish({ ...base, boxLanguage: "en", acceptLanguage: "de" })).toBe(false);
  });

  it("remembers the EL/EN choice per site", () => {
    const cookie = siteLanguageCookie("crossfit-kypseli", "en", true);
    expect(cookie).toContain("Secure");
    const value = cookie.split(";")[0]!.split("=")[1];
    expect(rememberedSiteLanguage(value, "crossfit-kypseli")).toBe("en");
    expect(rememberedSiteLanguage(value, "other-box")).toBeNull();
    expect(rememberedSiteLanguage(undefined, "crossfit-kypseli")).toBeNull();
  });

  it("uses the owner's English text on /en and the original elsewhere or when empty", () => {
    expect(siteText("en", "Γεια", "Hello")).toBe("Hello");
    expect(siteText("en", "Γεια", "  ")).toBe("Γεια");
    expect(siteText("box", "Γεια", "Hello")).toBe("Γεια");
  });

  it("keeps an English FAQ entry only when both halves are there", () => {
    const entries = [
      { question: "Ερώτηση;", answer: "Απάντηση", question_en: "Question?", answer_en: "Answer" },
      { question: "Μόνο ελληνικά;", answer: "Ναι", question_en: "Only Greek?" },
    ];
    expect(faqFor("en", entries)).toEqual([
      { question: "Question?", answer: "Answer" },
      { question: "Μόνο ελληνικά;", answer: "Ναι" },
    ]);
    expect(faqFor("box", entries)[0]).toEqual({ question: "Ερώτηση;", answer: "Απάντηση" });
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
