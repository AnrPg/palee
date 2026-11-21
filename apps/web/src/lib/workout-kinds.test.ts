import { describe, expect, it } from "vitest";

import { closeWorkoutKinds } from "@/components/workouts/WorkoutTypesField";
import { workoutFamiliesLook } from "@/lib/theme";
import {
  foldKindLabel,
  kindFamilies,
  kindFamily,
  mergeCatalogues,
  sortKindRefs,
  workoutKindFamilies,
  workoutKindRefs,
  type WorkoutKindCatalogue,
} from "@/lib/workout-kinds";

const boxId = "4f1c2b7e-1d2c-4a1b-9c3d-2e1f0a9b8c7d";
const mergedId = "5a2d3c8f-2e3d-4b2c-8d4e-3f2a1b0c9d8e";
const catalogue: WorkoutKindCatalogue = {
  additions: [{ key: "animal_flow", family: "mind_body", labels: { en: "Animal flow", el: "Animal flow" } }],
  box: [
    { id: boxId, ref: `box:${boxId}`, label: "Engine", family: "endurance", status: "active", merged_into: null },
    { id: mergedId, ref: `box:${mergedId}`, label: "Old", family: "strength", status: "merged", merged_into: "crossfit" },
  ],
};

describe("ADR-690 workout kinds", () => {
  it("names a family for every kind of reference; a merged box type follows its target", () => {
    expect(kindFamily("strength", catalogue)).toBe("strength");
    expect(kindFamily("animal_flow", catalogue)).toBe("mind_body");
    expect(kindFamily(`box:${boxId}`, catalogue)).toBe("endurance");
    expect(kindFamily(`box:${mergedId}`, catalogue)).toBe("functional");
    expect(kindFamily("unheard_of", catalogue)).toBeNull();
  });

  it("lists families once each in catalogue order, and prefers the API's families", () => {
    expect(kindFamilies([`box:${boxId}`, "crossfit", "hyrox", "strength"], catalogue)).toEqual(["functional", "strength", "endurance"]);
    expect(workoutKindFamilies({ type: "yoga", types: ["yoga"], families: ["recovery"] })).toEqual(["recovery"]);
    expect(workoutKindFamilies({ type: "yoga" })).toEqual(["mind_body"]);
  });

  it("reads an old WOD's single type", () => {
    expect(workoutKindRefs({ type: "crossfit" })).toEqual(["crossfit"]);
    expect(workoutKindRefs({ type: null, types: [] })).toEqual([]);
  });

  it("orders built-ins, then additions, then box types by name", () => {
    expect(sortKindRefs([`box:${boxId}`, "animal_flow", "strength", "crossfit"], catalogue, () => "Engine")).toEqual([
      "crossfit",
      "strength",
      "animal_flow",
      `box:${boxId}`,
    ]);
  });

  it("folds names like the API and finds close ones for «Μήπως εννοείς…»", () => {
    expect(foldKindLabel("  Ζώνη   ΤΑΧΥΤΗΤΑΣ ")).toBe("ζωνη ταχυτητασ");
    const options = [{ folded: "hyrox" }, { folded: "yoga" }, { folded: "running" }];
    expect(closeWorkoutKinds("Hyroks", options)).toEqual([{ folded: "hyrox" }]);
    expect(closeWorkoutKinds("Hyrox sim", options)).toEqual([{ folded: "hyrox" }]);
    expect(closeWorkoutKinds("Pole", options)).toEqual([]);
  });

  it("merges catalogues, the later read winning", () => {
    const fresher = { additions: [], box: [{ ...catalogue.box[0]!, label: "Engine room" }] };
    expect(mergeCatalogues(catalogue, fresher).box.find((kind) => kind.id === boxId)?.label).toBe("Engine room");
  });

  it("splits a mixed WOD's stripe into its families' colours", () => {
    expect(workoutFamiliesLook(["strength"])).toMatchObject({ mixed: false, stripe: "var(--workout-strength)" });
    const mixed = workoutFamiliesLook(["functional", "endurance"]);
    expect(mixed.mixed).toBe(true);
    expect(mixed.stripe).toContain("var(--workout-crossfit) 0.00% 50.00%");
    expect(mixed.stripe).toContain("var(--workout-aerobics) 50.00% 100.00%");
  });
});
