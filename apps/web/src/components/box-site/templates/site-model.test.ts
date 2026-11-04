import { describe, expect, it } from "vitest";

import type { SiteSection } from "@/api/box-site";

import { contrast, siteTokens, PALETTE_KEYS } from "./palettes";
import { pageIsShown, siteCta, sitePagePath, sitePages, siteSegment } from "./site-model";

const s = (...keys: string[]) => keys as SiteSection[];

describe("siteSegment (the segment after /b/<slug>/)", () => {
  const languages = ["el", "en", "pt-PT"];
  it("names a page in the box's language or one of its translations", () => {
    expect(siteSegment("schedule", languages)).toEqual({ kind: "page", page: "schedule" });
    expect(siteSegment("Coaches", languages)).toEqual({ kind: "page", page: "coaches" });
    expect(siteSegment("en", languages)).toEqual({ kind: "language", code: "en" });
    expect(siteSegment("pt-pt", languages)).toEqual({ kind: "language", code: "pt-PT" });
  });
  it("rejects anything else, the home page included", () => {
    expect(siteSegment("home", languages)).toBeNull();
    expect(siteSegment("de", languages)).toBeNull();
    expect(siteSegment("", languages)).toBeNull();
  });
});

describe("pageIsShown (a page without sections redirects home)", () => {
  it("follows the menu", () => {
    expect(pageIsShown("home", s("hero"))).toBe(true);
    expect(pageIsShown("coaches", s("hero", "about"))).toBe(false);
    expect(pageIsShown("coaches", s("hero", "coaches"))).toBe(true);
    expect(pageIsShown("schedule", s("events"))).toBe(true);
    expect(pageIsShown("space", s("faq"))).toBe(true);
  });
});

describe("sitePages", () => {
  it("drops pages with nothing on them", () => {
    expect(sitePages(s("hero", "about", "packages", "location")).map((p) => p.key)).toEqual(["home", "packages", "space"]);
  });
  it("names the schedule page «training» without the timetable", () => {
    expect(sitePages(s("hero", "events")).find((p) => p.key === "schedule")?.label).toBe("training");
  });
});

describe("siteCta", () => {
  it("falls back from trial to contact to call", () => {
    expect(siteCta({ trial: true, contact: true }, "210").kind).toBe("trial");
    expect(siteCta({ trial: false, contact: true }, "210").kind).toBe("contact");
    expect(siteCta({ trial: false, contact: false }, "210").kind).toBe("call");
    expect(siteCta({ trial: false, contact: false }, null).kind).toBe("none");
  });
});

describe("sitePagePath", () => {
  it("builds paths under the base and on the box's own domain", () => {
    expect(sitePagePath("/b/kypseli", "packages")).toBe("/b/kypseli/packages");
    expect(sitePagePath("", "home")).toBe("/");
    expect(sitePagePath("", "space")).toBe("/space");
  });
});

describe("siteTokens", () => {
  it("keeps accent text at WCAG AA for every palette, light and dark, in every template", () => {
    for (const palette of PALETTE_KEYS) {
      for (const dark of [false, true]) {
        for (const template of ["arena", "tiles", "stories", "atelier"] as const) {
          const { tokens } = siteTokens(palette, dark, template);
          expect(contrast(tokens["--s-accent-ink"], tokens["--s-bg"])).toBeGreaterThanOrEqual(4.5);
          expect(contrast(tokens["--s-ink"], tokens["--s-bg"])).toBeGreaterThanOrEqual(4.5);
        }
      }
    }
  });
});
