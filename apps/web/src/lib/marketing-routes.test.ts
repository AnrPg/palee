import { describe, expect, it } from "vitest";

import { MARKETING_TAB_HREF, movedAdminPageRedirect, movedAdminTarget } from "./marketing-routes";

const target = (path: string, query = "") => movedAdminTarget(path, new URLSearchParams(query));

describe("movedAdminTarget (ANR 2026-11-04)", () => {
  it("sends the old challenges page to Μάρκετινγκ › Challenges", () => {
    expect(target("/admin/challenges")).toBe("/admin/marketing/challenges");
    expect(target("/admin/challenges/")).toBe("/admin/marketing/challenges");
  });

  it("sends Οικονομικά › Προσφορές to the box's promotions, keeping an open campaign or form", () => {
    expect(target("/admin/finance", "tab=promotions")).toBe("/admin/marketing/promotions");
    expect(target("/admin/finance", "tab=promotions&campaign=c1")).toBe("/admin/marketing/promotions?campaign=c1");
    expect(target("/admin/finance", "tab=promotions&new=true")).toBe("/admin/marketing/promotions?new=true");
  });

  it("sends the partner segment to partner perks", () => {
    expect(target("/admin/finance", "tab=promotions&offers=partners")).toBe("/admin/marketing/perks");
  });

  it("sends Οικονομικά › Συστάσεις to referrals, keeping the open sheet", () => {
    expect(target("/admin/finance", "tab=referrals")).toBe("/admin/marketing/referrals");
    expect(target("/admin/finance", "tab=referrals&referral-event=e1")).toBe("/admin/marketing/referrals?referral-event=e1");
  });

  it("sends the old marketing page and /admin/marketing to the Marketing tab", () => {
    expect(target("/admin/metrics/marketing")).toBe(MARKETING_TAB_HREF);
    expect(target("/admin/marketing")).toBe(MARKETING_TAB_HREF);
  });

  it("leaves the pages that did not move alone", () => {
    expect(target("/admin/finance")).toBeNull();
    expect(target("/admin/finance", "tab=packages")).toBeNull();
    expect(target("/admin/finance", "tab=offers")).toBeNull();
    expect(target("/admin/marketing/promotions")).toBeNull();
    expect(target("/admin/metrics", "tab=marketing")).toBeNull();
  });
});

describe("movedAdminPageRedirect", () => {
  it("keeps the /org/<slug> prefix", () => {
    const next = movedAdminPageRedirect(new URL("https://palee.app/org/kypseli/admin/finance?tab=promotions&offers=partners"));
    expect(next?.toString()).toBe("https://palee.app/org/kypseli/admin/marketing/perks");
  });

  it("ignores everything outside the console", () => {
    expect(movedAdminPageRedirect(new URL("https://palee.app/me/referrals?tab=invites"))).toBeNull();
    expect(movedAdminPageRedirect(new URL("https://palee.app/org/kypseli/admin"))).toBeNull();
  });
});
