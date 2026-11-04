import { describe, expect, it } from "vitest";

import type { SiteSection } from "@/api/box-site";

import { changedGroups, effectiveSite, LISTED_SECTIONS, publishedLook, quickSections, sectionWrite, type LooseSiteSettings } from "./website-draft-model";

const base = {
  banner_version: 1,
  conversions_api_enabled: false,
  faq: [],
  forms_enabled: true,
  ga4_measurement_id: null,
  gtm_container_id: null,
  has_conversions_api_token: false,
  hidden_sections: [],
  lock_version: 3,
  meta_pixel_id: null,
  public_schedule: false,
  public_wod: false,
  section_order: ["hero", "about"],
  translation_locales: [],
  visible_locales: [],
} as unknown as LooseSiteSettings;

const settings = (extra: Partial<LooseSiteSettings> = {}): LooseSiteSettings => ({ ...base, ...extra });

// ADR-530 §2: template, colours, motion and the switches are a draft until «Δημοσίευση».
describe("the website draft", () => {
  it("fills what an older API leaves out: «Αρένα», Palee, automatic, normal motion", () => {
    expect(publishedLook(settings())).toEqual({ template: "arena", palette: "palee", appearance: "auto", calm_motion: false });
    expect(effectiveSite(settings()).template).toBe("arena");
  });

  it("overlays the draft and then the clicks not saved yet on the published values", () => {
    const site = settings({ template: "tiles", palette: "palee", draft: { palette: "flame", public_schedule: true } });
    const next = effectiveSite(site, { appearance: "dark" });
    expect(next).toMatchObject({ template: "tiles", palette: "flame", appearance: "dark", public_schedule: true, public_wod: false });
  });

  it("names only what differs from the published site, in the bar's order", () => {
    expect(changedGroups(settings({ template: "arena" }))).toEqual([]);
    expect(changedGroups(settings({ draft: { template: "arena" } }))).toEqual([]);
    expect(
      changedGroups(settings({ draft: { calm_motion: true, palette: "olive", template: "atelier", appearance: "light", hidden_sections: ["faq"] } })),
    ).toEqual(["template", "colors", "appearance", "motion", "sections"]);
    expect(changedGroups(settings({ hidden_sections: ["faq", "about"] }), { hidden_sections: ["about", "faq"] })).toEqual([]);
    expect(changedGroups(settings(), { public_wod: true })).toEqual(["sections"]);
  });

  it("keeps the forms on the live site while their switches are a draft", () => {
    const state = { hidden_sections: ["trial_form"] as SiteSection[], public_schedule: false, public_wod: false, forms_enabled: true };
    expect(sectionWrite(state, "contact_form", false)).toEqual({ hidden_sections: ["trial_form", "contact_form"] });
    // An older site with the forms off: switching one on turns them on (that field saves at once).
    expect(sectionWrite({ ...state, forms_enabled: false }, "trial_form", true)).toEqual({ hidden_sections: ["contact_form"], forms_enabled: true });
  });

  it("«Μόνο τα βασικά» keeps about, packages, location and the trial form; «Όλα» turns everything on", () => {
    const state = { hidden_sections: [] as SiteSection[], public_schedule: true, public_wod: true, forms_enabled: true };
    const basic = quickSections(state, "basic");
    expect(LISTED_SECTIONS.filter((key) => !basic.hidden_sections!.includes(key))).toEqual(["about", "packages", "location", "trial_form"]);
    expect(basic).toMatchObject({ public_schedule: false, public_wod: false });
    expect(basic.forms_enabled).toBeUndefined();
    expect(quickSections({ ...state, forms_enabled: false }, "all")).toEqual({ hidden_sections: [], public_schedule: true, public_wod: true, forms_enabled: true });
  });
});
