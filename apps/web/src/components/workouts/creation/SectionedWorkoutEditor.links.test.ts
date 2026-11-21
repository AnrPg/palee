import { describe, expect, it } from "vitest";

import type { ExerciseMatch } from "@/api/exercise-matches";
import type { EditorTextSection } from "@/lib/text-sections";

import { linkSections } from "./SectionedWorkoutEditor";

function section(key: string, lines: string[]): EditorTextSection {
  return {
    key,
    title: "",
    body: lines.join("\n"),
    document: { type: "doc", content: lines.map((text) => ({ type: "paragraph", content: [{ type: "text", text }] })) },
    preset: { format: "untimed" } as EditorTextSection["preset"],
    metrics: [],
  };
}

function match(sectionIndex: number, line: number, from: number, typed: string, ref: string): ExerciseMatch {
  return {
    id: `${sectionIndex}:${line}:${from}:${from + typed.length}`,
    section: sectionIndex,
    line,
    from,
    to: from + typed.length,
    typed,
    folded: typed.toLowerCase(),
    exercise_ref: ref,
    label: ref,
    kind: "fuzzy",
    remembered: false,
    muscles: [],
    qualities: [],
  };
}

describe("linkSections (ADR-671)", () => {
  it("links each answer in its own section and leaves the others as they were", () => {
    const sections = [section("a", ["Row 500m"]), section("b", ["21-15-9", "Thrustr"])];
    const linked = linkSections(sections, [
      { match: match(1, 1, 0, "Thrustr", "thruster"), ref: "thruster", checked: null },
      { match: match(0, 0, 0, "Row", "row"), ref: null, checked: null },
    ]);

    expect(JSON.stringify(linked[1]!.document)).toContain('"ref":"thruster"');
    expect(linked[1]!.contentVersion).toBe(1);
    expect(linked[1]!.body).toBe("21-15-9\nThrustr");
    // A «Όχι» is a link without an exercise.
    expect(JSON.stringify(linked[0]!.document)).toContain('"ref":null');
  });

  it("keeps a section whose words moved away untouched", () => {
    const sections = [section("a", ["Burpees"])];
    const linked = linkSections(sections, [{ match: match(0, 0, 0, "Thrustr", "thruster"), ref: "thruster", checked: null }]);
    expect(linked[0]).toBe(sections[0]);
  });
});
