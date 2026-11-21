import { describe, expect, it } from "vitest";

import type { WorkoutPreview } from "@/api/schedule";

import { wodOutline } from "./ClassSheet";

const base = { id: "w", title: "WOD", type: "strength" } as const;

describe("wodOutline", () => {
  it("shows every part's movements in order", () => {
    const workout: WorkoutPreview = {
      ...base,
      authoring_mode: "structured",
      sections: [
        { id: "b", name: "Metcon", order: 2, exercises: [{ id: "2", name: "Pull-up", order: 2 } as never, { id: "1", name: "Thruster", order: 1 } as never] },
        { id: "a", name: "Warm-up", order: 1, exercises: [{ id: "3", name: "Row", order: 1 } as never] },
      ],
    };
    expect(wodOutline(workout)).toEqual([
      { id: "a", name: "Warm-up", movements: ["Row"], text: "" },
      { id: "b", name: "Metcon", movements: ["Thruster", "Pull-up"], text: "" },
    ]);
  });

  it("shows a text section's whole text, never only its title (ADR-180)", () => {
    const workout: WorkoutPreview = {
      ...base,
      authoring_mode: "sectioned_text",
      sections: [
        { id: "a", name: "A. Strength", order: 1, exercises: [], free_text_body: "Back squat 5x5\n" },
        { id: "b", name: "Section 2", order: 2, exercises: [], free_text_body: "AMRAP 12\n10 thrusters", section_metadata: { untitled: true } },
      ],
    };
    expect(wodOutline(workout)).toEqual([
      { id: "a", name: "A. Strength", movements: [], text: "Back squat 5x5" },
      { id: "b", name: "", movements: [], text: "AMRAP 12\n10 thrusters" },
    ]);
  });

  it("leaves a free-text WOD whose parts carry no movements to its text", () => {
    const workout: WorkoutPreview = {
      ...base,
      authoring_mode: "free_text",
      free_text_body: "Strength\nBack squat 5x5",
      sections: [{ id: "a", name: "Strength", order: 1, exercises: [] }],
    };
    expect(wodOutline(workout)).toEqual([]);
  });
});
