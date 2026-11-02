import type { SiteSection } from "@/api/box-site";

/**
 * The website's section switches (ANR s1 A). Some sections also hang on a
 * setting of their own: «Ωρολόγιο» on `public_schedule`, «WOD της ημέρας» on
 * `public_wod` (both off by default) and the two forms on `forms_enabled`.
 * One switch per section sets both, so the owner sees a single control.
 */
export type SectionState = {
  section_order: SiteSection[];
  hidden_sections: SiteSection[];
  public_schedule: boolean;
  public_wod: boolean;
  forms_enabled: boolean;
};

const FORMS: SiteSection[] = ["trial_form", "contact_form"];

export function sectionOn(state: SectionState, key: SiteSection) {
  if (key === "hero") return true;
  if (state.hidden_sections.includes(key)) return false;
  if (key === "schedule") return state.public_schedule;
  if (key === "wod") return state.public_wod;
  if (FORMS.includes(key)) return state.forms_enabled;
  return true;
}

export function toggleSection(state: SectionState, key: SiteSection, on: boolean): Partial<SectionState> {
  if (key === "hero") return {};
  const hidden = on ? state.hidden_sections.filter((entry) => entry !== key) : [...new Set([...state.hidden_sections, key])];
  const patch: Partial<SectionState> = { hidden_sections: hidden };
  if (key === "schedule") patch.public_schedule = on;
  if (key === "wod") patch.public_wod = on;
  if (FORMS.includes(key)) {
    if (on) {
      patch.forms_enabled = true;
      // Turning the forms on again must not bring back the other form the owner had off.
      if (!state.forms_enabled) patch.hidden_sections = [...new Set([...hidden, ...FORMS.filter((form) => form !== key)])];
    } else {
      patch.forms_enabled = FORMS.some((form) => form !== key && !hidden.includes(form));
    }
  }
  return patch;
}

/** Moves a section one place up (-1) or down (1); «hero» stays first. */
export function moveSection(order: SiteSection[], key: SiteSection, step: -1 | 1): SiteSection[] {
  const index = order.indexOf(key);
  const target = index + step;
  if (key === "hero" || index < 0 || target < 1 || target >= order.length) return order;
  const next = [...order];
  next[index] = next[target]!;
  next[target] = key;
  return next;
}

/** The tag fields under «Προχωρημένα»: product names and id formats, the same in every language. */
export const TAG_FIELDS = [
  { key: "ga4_measurement_id", label: "Google Analytics 4", placeholder: "G-XXXXXXX" },
  { key: "gtm_container_id", label: "Google Tag Manager", placeholder: "GTM-XXXXXX" },
  { key: "meta_pixel_id", label: "Meta Pixel", placeholder: "1234567890" },
] as const;
export const CONVERSIONS_API_LABEL = "Meta Conversions API";
export const DOMAIN_PLACEHOLDER = "www.mybox.gr";
