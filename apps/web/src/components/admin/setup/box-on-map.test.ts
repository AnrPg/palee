import { describe, expect, it } from "vitest";

import { boxFindableByPlace } from "./box-on-map";

const location = (overrides: Record<string, unknown>) => ({ archived_at: null, city: null, latitude: null, longitude: null, ...overrides });

describe("boxFindableByPlace (ADR-583 Ε4)", () => {
  it("is false without any location, or with only archived or placeless ones", () => {
    expect(boxFindableByPlace([])).toBe(false);
    expect(boxFindableByPlace([location({ city: "  " })])).toBe(false);
    expect(boxFindableByPlace([location({ city: "Βόλος", archived_at: "2026-11-01T00:00:00Z" })])).toBe(false);
  });

  it("is true once a live location has a town or a map pin", () => {
    expect(boxFindableByPlace([location({ city: "Βόλος" })])).toBe(true);
    expect(boxFindableByPlace([location({ latitude: 39.36, longitude: 22.94 })])).toBe(true);
  });
});
