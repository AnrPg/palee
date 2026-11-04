import { describe, expect, it } from "vitest";

import type { SiteSection } from "@/api/box-site";

import { sectionOn, toggleSection, type SectionState } from "./website-settings-model";

const STATE: SectionState = { hidden_sections: [], public_schedule: false, public_wod: false, forms_enabled: true };

// ANR s1 A: one switch per section; Ωρολόγιο and WOD της ημέρας are off by default.
describe("website sections", () => {
  it("shows the timetable and the WOD off until their switch is on", () => {
    expect(sectionOn(STATE, "schedule")).toBe(false);
    expect(sectionOn(STATE, "wod")).toBe(false);
    expect(sectionOn(STATE, "about")).toBe(true);
    expect(sectionOn(STATE, "hero")).toBe(true);
  });

  it("turns the timetable on with its own setting", () => {
    expect(toggleSection(STATE, "schedule", true)).toEqual({ hidden_sections: [], public_schedule: true });
    expect(toggleSection(STATE, "wod", true)).toEqual({ hidden_sections: [], public_wod: true });
  });

  it("turns the forms off only when both are off, and back on without the other", () => {
    const one = { ...STATE, ...toggleSection(STATE, "trial_form", false) };
    expect(one.forms_enabled).toBe(true);
    const both = { ...one, ...toggleSection(one, "contact_form", false) };
    expect(both.forms_enabled).toBe(false);
    const again = { ...both, ...toggleSection(both, "trial_form", true) };
    expect(sectionOn(again, "trial_form")).toBe(true);
    expect(sectionOn(again, "contact_form")).toBe(false);
  });

  it("never hides the hero", () => {
    expect(toggleSection(STATE, "hero", false)).toEqual({});
  });

  it("treats the new sections (ADR-530) like any other switch", () => {
    const photos = "photos" as SiteSection;
    expect(sectionOn(STATE, photos)).toBe(true);
    expect(toggleSection(STATE, photos, false)).toEqual({ hidden_sections: [photos] });
  });
});
