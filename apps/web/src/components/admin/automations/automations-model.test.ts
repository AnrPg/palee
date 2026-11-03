import { describe, expect, it } from "vitest";

import type { Recipe } from "@/api/leads";

import { changes, draftOf, hasDelay, sentCount, settingValue, toggleChannel, validateDraft } from "./automations-model";

function recipe(overrides: Partial<Recipe> = {}): Recipe {
  return {
    key: "missed_classes",
    trigger: "daily",
    enabled: false,
    channels: [],
    default_channels: ["push", "email"],
    subject: null,
    default_subject: "We miss you",
    body: null,
    default_body: "Hi {first_name}",
    settings: { days_absent: 10 },
    delay_minutes: null,
    default_delay_minutes: 0,
    stats: { sent: 4 },
    ...overrides,
  } as unknown as Recipe;
}

describe("automations model", () => {
  it("reads the tunable number and whether a recipe can wait", () => {
    expect(settingValue(recipe())).toBe(10);
    expect(settingValue(recipe({ key: "welcome" } as Partial<Recipe>))).toBeNull();
    expect(hasDelay(recipe())).toBe(false);
    expect(hasDelay(recipe({ trigger: "event" } as Partial<Recipe>))).toBe(true);
    expect(sentCount(recipe())).toBe(4);
  });

  it("keeps the order channels were chosen in", () => {
    expect(toggleChannel(["email"], "push")).toEqual(["email", "push"]);
    expect(toggleChannel(["email", "push"], "email")).toEqual(["push"]);
  });

  it("starts the draft from the defaults", () => {
    expect(draftOf(recipe())).toEqual({ enabled: false, channels: ["push", "email"], subject: "We miss you", body: "Hi {first_name}", setting: "10", delay: "0" });
  });

  it("checks the setting's range, the channels and the texts", () => {
    const draft = { ...draftOf(recipe()), setting: "70", channels: [], body: " " };
    expect(validateDraft(recipe(), draft)).toEqual({ channels: "required", body: "required", setting: "range" });
    expect(validateDraft(recipe(), draftOf(recipe()))).toEqual({});
  });

  it("sends only what changed, and a text equal to the default as null", () => {
    const base = recipe({ subject: "Custom" } as Partial<Recipe>);
    const draft = { ...draftOf(base), enabled: true, subject: "We miss you", setting: "14" };
    expect(changes(base, draft)).toEqual({ enabled: true, subject: null, settings: { days_absent: 14 } });
    expect(changes(base, draftOf(base))).toEqual({});
  });
});
