import { describe, expect, it } from "vitest";

import en from "../../../messages/en.json";
import { AUDIENCES, COMPARISON, DAY, FEATURES, GRID_COLUMNS, MANAGEMENT, STORIES, audienceFromParam, gridHoles } from "./content";

const messages = (en as Record<string, unknown>).BusinessLanding as Record<string, Record<string, unknown>>;
const has = (path: string) =>
  path.split(".").reduce<unknown>((node, key) => (node && typeof node === "object" ? (node as Record<string, unknown>)[key] : undefined), messages) !== undefined;

describe("business landing content (ADR-556)", () => {
  it("fills every bento edge to edge at every screen size", () => {
    for (const audience of AUDIENCES) {
      for (const columns of GRID_COLUMNS) {
        expect(gridHoles(FEATURES[audience], columns), `${audience} features, ${columns} columns`).toBe(0);
        expect(gridHoles(MANAGEMENT[audience], columns), `${audience} management, ${columns} columns`).toBe(0);
      }
    }
  });

  it("counts a hole when a row cannot be filled", () => {
    expect(gridHoles([{ wide: true }, { wide: false }], 4)).toBe(1);
  });

  it("keeps the box-only running of the business away from coaches", () => {
    const coach = MANAGEMENT.coach.map((tile) => tile.visual);
    for (const visual of ["staffPay", "cleaning", "machines", "stock"] as const) expect(coach).not.toContain(visual);
    expect(COMPARISON.find((row) => row.id === "staffPay")?.coach).toBe(false);
  });

  it("has copy for every tile, step, story and row", () => {
    for (const audience of AUDIENCES) {
      for (const tile of [...FEATURES[audience], ...MANAGEMENT[audience]]) {
        for (const part of ["kicker", "title", "body"]) expect(has(`tiles.${tile.id}.${part}`), `${tile.id}.${part}`).toBe(true);
      }
      for (const step of DAY[audience]) {
        for (const part of ["time", "title", "body"]) expect(has(`how.${audience}.${step.id}.${part}`)).toBe(true);
      }
      for (const story of STORIES[audience]) {
        for (const part of ["kicker", "title", "body"]) expect(has(`stories.${audience}.${story.id}.${part}`)).toBe(true);
      }
    }
    for (const row of COMPARISON) expect(has(`compare.rows.${row.id}`)).toBe(true);
  });

  it("reads the audience from ?for=", () => {
    expect(audienceFromParam("coach")).toBe("coach");
    expect(audienceFromParam(["coach"])).toBe("coach");
    expect(audienceFromParam("box")).toBe("box");
    expect(audienceFromParam("anything")).toBe("box");
    expect(audienceFromParam(undefined)).toBe("box");
  });
});
