import { describe, expect, it } from "vitest";

import { firstStaffRole, usesAppAsAthlete } from "./athlete-use";

const box = (name: string) => ({ name });

describe("usesAppAsAthlete (ADR-463)", () => {
  it("is false only when the person said they do not train", () => {
    expect(usesAppAsAthlete({ trains_with_palee: false })).toBe(false);
    expect(usesAppAsAthlete({ trains_with_palee: true })).toBe(true);
  });

  it("treats never asked, a missing field and no user as training", () => {
    expect(usesAppAsAthlete({ trains_with_palee: null })).toBe(true);
    expect(usesAppAsAthlete({})).toBe(true);
    expect(usesAppAsAthlete(null)).toBe(true);
    expect(usesAppAsAthlete(undefined)).toBe(true);
  });
});

describe("firstStaffRole", () => {
  it("is null for members, athletes and guests", () => {
    expect(firstStaffRole([{ role: "member", organization: box("A") }])).toBeNull();
    expect(firstStaffRole([{ role: "athlete", roles: ["athlete"], organization: box("A") }])).toBeNull();
    expect(firstStaffRole([{ role: "guest", organization: box("A") }])).toBeNull();
    expect(firstStaffRole(undefined)).toBeNull();
  });

  it("finds the first membership with a staff role and its highest staff role", () => {
    const staff = { role: "member", roles: ["member", "front_desk", "coach"], organization: box("B") };
    const found = firstStaffRole([{ role: "member", organization: box("A") }, staff]);
    expect(found?.membership).toBe(staff);
    expect(found?.role).toBe("coach");
  });

  it("covers every staff role, cleaning staff included", () => {
    for (const role of ["owner", "admin", "coach", "front_desk", "accountant", "janitor"]) {
      expect(firstStaffRole([{ role, organization: box("A") }])?.role).toBe(role);
    }
  });
});
