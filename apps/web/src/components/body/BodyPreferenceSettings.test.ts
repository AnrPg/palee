import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import { splitUnitsLabel } from "./BodyPreferenceSettings";

const MESSAGES = join(__dirname, "../../../messages");

describe("splitUnitsLabel", () => {
  it("puts the units in parentheses on their own line", () => {
    expect(splitUnitsLabel("Μετρικό (kg, cm)")).toEqual({ name: "Μετρικό", units: "(kg, cm)" });
    expect(splitUnitsLabel("Αγγλοσαξονικό (lb, in)")).toEqual({ name: "Αγγλοσαξονικό", units: "(lb, in)" });
  });

  it("keeps a label without units on one line", () => {
    expect(splitUnitsLabel("Metric")).toEqual({ name: "Metric", units: null });
  });

  it("splits the units label of every locale", () => {
    for (const file of readdirSync(MESSAGES).filter((name) => name.endsWith(".json"))) {
      const units = JSON.parse(readFileSync(join(MESSAGES, file), "utf8")).Body.units as Record<string, string>;
      for (const label of Object.values(units)) {
        const { name, units: detail } = splitUnitsLabel(label);
        expect(detail, `${file}: ${label}`).toMatch(/^\(.+\)$/);
        expect(name.length, `${file}: ${label}`).toBeGreaterThan(0);
      }
    }
  });
});
