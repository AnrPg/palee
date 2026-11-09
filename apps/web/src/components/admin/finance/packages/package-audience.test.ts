import { describe, expect, it } from "vitest";

import type { PackageAudienceSettings } from "@/api/package-audience";

import { exceptionsFor, normalizeSettings, packageAudience, personName, personOptions } from "./package-audience";

const person = (id: string, nickname: string | null = id, handle: string | null = null) => ({ id, nickname, handle, avatar_url: null });

const settings: PackageAudienceSettings = {
  audience: "own",
  featured_package_id: null,
  exceptions: [
    { id: "e1", package_id: null, effect: "hide", person: person("nikos") },
    { id: "e2", package_id: "pkg", effect: "hide", person: person("eleni") },
    { id: "e3", package_id: null, effect: "show", person: person("maria") },
    { id: "e4", package_id: "pkg", effect: "show", person: person("acme") },
  ],
};

describe("package audience (ADR-553)", () => {
  it("reads a package's own choice, anything else follows the box", () => {
    expect(packageAudience({ audience: "own" })).toBe("own");
    expect(packageAudience({ audience: null })).toBeNull();
    expect(packageAudience({ audience: "maybe" })).toBeNull();
    expect(packageAudience(undefined)).toBeNull();
  });

  it("splits the exceptions by package, «show» before «hide»", () => {
    expect(exceptionsFor(settings, null).map((row) => row.id)).toEqual(["e3", "e1"]);
    expect(exceptionsFor(settings, "pkg").map((row) => row.id)).toEqual(["e4", "e2"]);
    expect(exceptionsFor(settings, "other")).toEqual([]);
    expect(exceptionsFor(undefined, null)).toEqual([]);
  });

  it("offers the box's people first, then anyone on Palee, each once", () => {
    const members = [
      { id: "m1", nickname: "Μαρία", role: "member" },
      { id: "m2", nickname: "Νίκος", role: "member" },
    ];
    const people = [
      { id: "m1", nickname: "Μαρία", handle: "maria", buddy: false, my_status: "none", relation: "public" },
      { id: "p1", nickname: null, handle: "acme_hr", buddy: false, my_status: "none", relation: "public" },
      { id: "p2", nickname: null, handle: null, buddy: false, my_status: "none", relation: "public" },
    ] as const;
    const options = personOptions(members, [...people], ["m2"]);
    expect(options).toEqual([
      { id: "m1", label: "Μαρία", handle: null, member: true },
      { id: "p1", label: "@acme_hr", handle: "acme_hr", member: false },
    ]);
  });

  it("names a person by name, else @handle", () => {
    expect(personName(person("x", "Μαρία"))).toBe("Μαρία");
    expect(personName(person("x", null, "maria"))).toBe("@maria");
    expect(personName(person("x", null, null))).toBeNull();
  });
  it("reads an empty or odd answer as «Όλα» with no exceptions", () => {
    expect(normalizeSettings({})).toEqual({ audience: "all", exceptions: [], featured_package_id: null });
    expect(normalizeSettings({ featured_package_id: "p1" }).featured_package_id).toBe("p1");
    expect(normalizeSettings({ audience: "x", exceptions: "nope" })).toEqual({ audience: "all", exceptions: [], featured_package_id: null });
    expect(personOptions({} as never, undefined as never, [])).toEqual([]);
  });
});
