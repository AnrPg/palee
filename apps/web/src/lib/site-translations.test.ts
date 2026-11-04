import { describe, expect, it } from "vitest";

import type { SiteLanguages } from "@/api/box-site";

import {
  addableLanguages,
  addLanguage,
  filterCounts,
  groupItems,
  languageName,
  machineDue,
  matchesFilter,
  progressFor,
  readyPercent,
  removeLanguage,
  showLanguage,
  siteTextFor,
  sourceEditPath,
  workQueue,
} from "./site-translations";

const items = [
  { key: "a", group: "faq", status: "ok" },
  { key: "b", group: "about", status: "missing" },
  { key: "c", group: "packages", status: "stale" },
  { key: "d", group: "faq", status: "machine" },
] as const;

const languages: SiteLanguages = {
  source: "el",
  available: ["en", "de", "fr"],
  machine_available: true,
  progress: [{ locale: "en", counts: { ok: 3, missing: 1, stale: 0, machine: 0 }, total: 4 }],
};

describe("site translations (ADR-520)", () => {
  it("filters by status, with «todo» being everything not ready", () => {
    expect(items.filter((item) => matchesFilter(item, "todo")).map((item) => item.key)).toEqual(["b", "c", "d"]);
    expect(items.filter((item) => matchesFilter(item, "stale")).map((item) => item.key)).toEqual(["c"]);
    expect(items.filter((item) => matchesFilter(item, "all"))).toHaveLength(4);
  });

  it("groups in the website's order and drops empty groups", () => {
    expect(groupItems([...items], "all").map((entry) => entry.group)).toEqual(["about", "faq", "packages"]);
    expect(groupItems([...items], "machine")).toEqual([{ group: "faq", items: [items[3]] }]);
  });

  it("keeps a text already in view after it no longer matches the filter", () => {
    const fixed = items.map((item) => (item.key === "b" ? { ...item, status: "ok" as const } : item));
    expect(groupItems(fixed, "todo").flatMap((entry) => entry.items.map((item) => item.key))).toEqual(["d", "c"]);
    expect(groupItems(fixed, "todo", new Set(["b"])).flatMap((entry) => entry.items.map((item) => item.key))).toEqual(["b", "d", "c"]);
  });

  it("queues the one-by-one view in the website's order", () => {
    expect(workQueue([...items]).map((item) => item.key)).toEqual(["b", "d", "c"]);
  });

  it("counts filters, readiness and machine work", () => {
    const counts = { ok: 1, missing: 2, stale: 3, machine: 4 };
    expect(filterCounts(counts, 10)).toEqual({ todo: 9, missing: 2, stale: 3, machine: 4, all: 10 });
    expect(readyPercent(counts, 10)).toBe(10);
    expect(readyPercent(counts, 0)).toBe(100);
    expect(machineDue(counts)).toBe(5);
  });

  it("names languages in their own language", () => {
    expect(languageName("de")).toBe("Deutsch");
    expect(languageName("xx")).toBe("xx");
  });

  it("shows a just-added language as all missing", () => {
    expect(progressFor(languages, "en")).toEqual({ counts: { ok: 3, missing: 1, stale: 0, machine: 0 }, total: 4 });
    expect(progressFor(languages, "de")).toEqual({ counts: { ok: 0, missing: 4, stale: 0, machine: 0 }, total: 4 });
  });

  it("adds hidden, shows in order and removes from both lists", () => {
    const start = { translation_locales: ["en"], visible_locales: ["en"] };
    expect(addableLanguages(languages, start.translation_locales)).toEqual(["de", "fr"]);
    const added = addLanguage(addLanguage(start, "de"), "fr");
    expect(added).toEqual({ translation_locales: ["en", "de", "fr"], visible_locales: ["en"] });
    expect(addLanguage(added, "de")).toBe(added);
    const shown = showLanguage(showLanguage(added, "fr", true), "de", true);
    expect(shown.visible_locales).toEqual(["en", "de", "fr"]);
    expect(showLanguage(shown, "en", false).visible_locales).toEqual(["de", "fr"]);
    expect(removeLanguage(shown, "de")).toEqual({ translation_locales: ["en", "fr"], visible_locales: ["en", "fr"] });
  });

  it("points each group to where its own text is edited", () => {
    expect(sourceEditPath({ group: "packages", id: "p1" })).toBe("/admin/finance/packages/p1");
    expect(sourceEditPath({ group: "about", id: "x" })).toBe("/admin/public-page");
    expect(sourceEditPath({ group: "faq", id: "x" })).toBe("/admin/settings/website");
  });

  it("uses a translation when there is one, else the box's text", () => {
    const texts = { "package:p1:name": "Monthly", "package:p1:description": "  " };
    expect(siteTextFor(texts, "package", "p1", "name", "Μηνιαίο")).toBe("Monthly");
    expect(siteTextFor(texts, "package", "p1", "description", "Περιγραφή")).toBe("Περιγραφή");
    expect(siteTextFor(null, "package", "p1", "name", null)).toBe("");
  });
});
