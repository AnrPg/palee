import type { Recipe, RecipeKey, RecipeUpdate } from "@/api/leads";

/** The number a box may tune per recipe (RecipeCatalog), with its bounds. */
export const RECIPE_SETTING: Partial<Record<RecipeKey, { name: string; min: number; max: number }>> = {
  missed_classes: { name: "days_absent", min: 5, max: 60 },
  renewal_reminder: { name: "days_before", min: 1, max: 30 },
};

/** Recipes started by an event can wait a while before sending (`delay_minutes`). */
export function hasDelay(recipe: Pick<Recipe, "trigger">): boolean {
  return recipe.trigger !== "daily";
}

export function settingValue(recipe: Pick<Recipe, "key" | "settings">): number | null {
  const setting = RECIPE_SETTING[recipe.key];
  if (!setting) return null;
  const value = (recipe.settings ?? {})[setting.name];
  return typeof value === "number" ? value : null;
}

/** Turns a channel on or off, keeping the order they were chosen in. */
export function toggleChannel(channels: string[], channel: string): string[] {
  return channels.includes(channel) ? channels.filter((entry) => entry !== channel) : [...channels, channel];
}

export type RecipeDraft = {
  enabled: boolean;
  channels: string[];
  subject: string;
  body: string;
  setting: string;
  delay: string;
};

export function draftOf(recipe: Recipe): RecipeDraft {
  return {
    enabled: recipe.enabled,
    channels: recipe.channels.length > 0 ? recipe.channels : recipe.default_channels,
    subject: recipe.subject ?? recipe.default_subject,
    body: recipe.body ?? recipe.default_body,
    setting: String(settingValue(recipe) ?? ""),
    delay: String(recipe.delay_minutes ?? recipe.default_delay_minutes),
  };
}

export type DraftErrors = Partial<Record<"channels" | "subject" | "body" | "setting" | "delay", "required" | "range">>;

export function validateDraft(recipe: Pick<Recipe, "key" | "trigger">, draft: RecipeDraft): DraftErrors {
  const errors: DraftErrors = {};
  if (draft.channels.length === 0) errors.channels = "required";
  if (!draft.subject.trim()) errors.subject = "required";
  if (!draft.body.trim()) errors.body = "required";
  const setting = RECIPE_SETTING[recipe.key];
  if (setting) {
    const value = Number(draft.setting);
    if (!Number.isInteger(value) || value < setting.min || value > setting.max) errors.setting = "range";
  }
  if (hasDelay(recipe)) {
    const value = Number(draft.delay);
    if (draft.delay.trim() === "" || !Number.isInteger(value) || value < 0 || value > 43_200) errors.delay = "range";
  }
  return errors;
}

/**
 * What to send: only what changed. A text equal to the default is sent as
 * null, so it keeps following the default in every language.
 */
export function changes(recipe: Recipe, draft: RecipeDraft): RecipeUpdate {
  const body: RecipeUpdate = {};
  const before = draftOf(recipe);
  if (draft.enabled !== before.enabled) body.enabled = draft.enabled;
  if (draft.channels.join(",") !== before.channels.join(",")) body.channels = draft.channels;
  if (draft.subject !== before.subject) body.subject = draft.subject.trim() === recipe.default_subject ? null : draft.subject.trim();
  if (draft.body !== before.body) body.body = draft.body.trim() === recipe.default_body ? null : draft.body.trim();
  const setting = RECIPE_SETTING[recipe.key];
  if (setting && draft.setting !== before.setting) body.settings = { [setting.name]: Number(draft.setting) };
  if (hasDelay(recipe) && draft.delay !== before.delay) body.delay_minutes = Number(draft.delay);
  return body;
}

/** Messages sent in the stats window (`stats.sent`). */
export function sentCount(recipe: Pick<Recipe, "stats">): number {
  return recipe.stats?.sent ?? 0;
}
