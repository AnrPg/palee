import { describe, expect, it } from "vitest";

import { holdersByRole, isAvailable, replacementCandidates } from "./package-availability";

describe("package availability («Διαθέσιμο / Αποσυρμένο»)", () => {
  it("a package is available unless it is retired (active: false)", () => {
    expect(isAvailable({ id: "a" })).toBe(true);
    expect(isAvailable({ id: "a", active: true })).toBe(true);
    expect(isAvailable({ id: "a", active: false })).toBe(false);
  });

  it("counts the members who hold the package, per account type", () => {
    const members = [
      { membership: { user_type_snapshot: "member" }, active_package_subscription: { membership_package_id: "p1" } },
      { membership: { user_type_snapshot: "member" }, active_package_subscription: { membership_package_id: "p1" } },
      { identity_role: "coach", active_package_subscription: { membership_package_id: "p1" } },
      { membership: { user_type_snapshot: "member" }, active_package_subscription: { membership_package_id: "p2" } },
      { membership: { user_type_snapshot: "member" }, active_package_subscription: null },
    ];
    expect(holdersByRole(members, "p1")).toEqual({ member: 2, coach: 1 });
    expect(holdersByRole(members, "p3")).toEqual({});
  });

  it("holders can only move to another available package", () => {
    const packages = [{ id: "p1" }, { id: "p2" }, { id: "p3", active: false }];
    expect(replacementCandidates(packages, "p1").map((pkg) => pkg.id)).toEqual(["p2"]);
  });
});
