import type { SiteDraft, SiteLook, SiteSection, SiteSettings, SiteSettingsV2 } from "@/api/box-site";

import { APPEARANCES, isPaletteKey, isTemplateKey } from "./templates/palettes";
import { BASIC_SECTIONS, SECTION_GROUPS } from "./templates/site-model";
import { toggleSection, type SectionState } from "./website-settings-model";

/**
 * ADR-530 §2: template, colours, motion and the section switches go live only
 * with «Δημοσίευση». The server keeps them in `draft` until then; the
 * settings page shows the published values overlaid with the draft (and with
 * the owner's newest clicks still on their way to the server).
 */

/** What the owner edits on the settings page and the server keeps as a draft. */
export type SiteDraftState = SiteLook & Pick<SiteSettings, "hidden_sections" | "public_schedule" | "public_wod">;
/** One change on its way to the server; `forms_enabled` is not a draft field and saves at once. */
export type SiteDraftPatch = Partial<SiteDraftState> & { forms_enabled?: boolean };
/** The groups the publish bar names. */
export type ChangedGroup = "template" | "colors" | "appearance" | "motion" | "sections";

/** Settings as the API sends them; the ADR-530 fields may still be missing (older API). */
export type LooseSiteSettings = SiteSettings & Partial<Omit<SiteSettingsV2, keyof SiteSettings>>;

/** Every section the page lists, in its groups' order. */
export const LISTED_SECTIONS: SiteSection[] = SECTION_GROUPS.flatMap((group) => group.sections);

/** The published look, with the defaults an older API leaves out (ADR-530: existing sites are «Αρένα»). */
export function publishedLook(settings: LooseSiteSettings): SiteLook {
  return {
    template: isTemplateKey(settings.template) ? settings.template : "arena",
    palette: isPaletteKey(settings.palette) ? settings.palette : "palee",
    appearance: (APPEARANCES as readonly string[]).includes(settings.appearance ?? "") ? settings.appearance! : "auto",
    calm_motion: settings.calm_motion ?? false,
  };
}

function published(settings: LooseSiteSettings): SiteDraftState {
  return {
    ...publishedLook(settings),
    hidden_sections: settings.hidden_sections,
    public_schedule: settings.public_schedule,
    public_wod: settings.public_wod,
  };
}

/** Published values, then the server's draft, then the clicks not yet saved. */
export function effectiveSite(settings: LooseSiteSettings, pending: SiteDraftPatch = {}): SiteDraftState & { forms_enabled: boolean } {
  const draft: SiteDraft = settings.draft ?? {};
  const known = Object.fromEntries(Object.entries(draft).filter(([, value]) => value !== undefined && value !== null)) as SiteDraft;
  const merged = { ...published(settings), forms_enabled: settings.forms_enabled, ...known, ...pending };
  return {
    ...merged,
    template: isTemplateKey(merged.template) ? merged.template : "arena",
    palette: isPaletteKey(merged.palette) ? merged.palette : "palee",
  };
}

function sameSet(a: readonly string[], b: readonly string[]) {
  const left = new Set(a);
  const right = new Set(b);
  return left.size === right.size && [...left].every((key) => right.has(key));
}

/** What differs from the published site, in the order the publish bar names it. */
export function changedGroups(settings: LooseSiteSettings, pending: SiteDraftPatch = {}): ChangedGroup[] {
  const live = published(settings);
  const next = effectiveSite(settings, pending);
  const groups: ChangedGroup[] = [];
  if (next.template !== live.template) groups.push("template");
  if (next.palette !== live.palette) groups.push("colors");
  if (next.appearance !== live.appearance) groups.push("appearance");
  if (next.calm_motion !== live.calm_motion) groups.push("motion");
  if (!sameSet(next.hidden_sections, live.hidden_sections) || next.public_schedule !== live.public_schedule || next.public_wod !== live.public_wod) {
    groups.push("sections");
  }
  return groups;
}

/**
 * One section switch as a write. The switches keep `toggleSection`'s meaning,
 * but a form switched off stays in `hidden_sections` (a draft field) rather
 * than turning `forms_enabled` off, which would take the forms off the live
 * site before «Δημοσίευση».
 */
export function sectionWrite(state: SectionState, key: SiteSection, on: boolean): SiteDraftPatch {
  const patch = toggleSection(state, key, on);
  if (patch.forms_enabled === false || patch.forms_enabled === state.forms_enabled) delete patch.forms_enabled;
  return patch;
}

/** «Όλα» turns every listed section on; «Μόνο τα βασικά» keeps the basic set. */
export function quickSections(state: SectionState, choice: "all" | "basic"): SiteDraftPatch {
  const keep = choice === "all" ? LISTED_SECTIONS : BASIC_SECTIONS;
  const hidden = LISTED_SECTIONS.filter((key) => !keep.includes(key));
  const patch: SiteDraftPatch = {
    hidden_sections: hidden,
    public_schedule: keep.includes("schedule"),
    public_wod: keep.includes("wod"),
  };
  if (!state.forms_enabled && keep.some((key) => key === "trial_form" || key === "contact_form")) patch.forms_enabled = true;
  return patch;
}
