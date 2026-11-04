import { describe, expect, it } from "vitest";

import type { SiteSection } from "@/api/box-site";

import { contrast, siteTokens, PALETTE_KEYS } from "./palettes";
import { siteCta, sitePagePath, sitePages } from "./site-model";

const s = (...keys: string[]) => keys as SiteSection[];

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
