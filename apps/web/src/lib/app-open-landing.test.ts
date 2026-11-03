import { beforeEach, describe, expect, it } from "vitest";

import { appOpenLanding, claimAppOpenLanding, noteRoute, resetAppOpenLanding } from "@/lib/app-open-landing";

describe("app-open landing (W7 screen 12)", () => {
  beforeEach(() => resetAppOpenLanding());

  it("a member of exactly one box opens on Box; others stay on Feed", () => {
    expect(appOpenLanding({ membershipCount: 1, vendor: false })).toBe("/box");
    expect(appOpenLanding({ membershipCount: 0, vendor: false })).toBeNull();
    expect(appOpenLanding({ membershipCount: 2, vendor: false })).toBeNull();
    expect(appOpenLanding({ membershipCount: 1, vendor: true })).toBeNull();
  });

  it("decides only once, for the first screen of the app open", () => {
    noteRoute("/");
    expect(claimAppOpenLanding("/")).toBe(true);
    expect(claimAppOpenLanding("/")).toBe(false);
  });

  it("tapping Feed after opening elsewhere never redirects", () => {
    noteRoute("/box");
    noteRoute("/");
    expect(claimAppOpenLanding("/")).toBe(false);
  });

  it("a first screen that is not Feed is never redirected later", () => {
    noteRoute("/journal");
    expect(claimAppOpenLanding("/")).toBe(false);
  });
});
