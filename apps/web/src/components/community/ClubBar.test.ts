import { describe, expect, it } from "vitest";

import { followedBoxBubbles } from "./ClubBar";

const box = (id: string) => ({ organization_id: id, slug: `box-${id}`, name: `Box ${id}`, logo_url: null });

describe("followedBoxBubbles (ADR-590)", () => {
  it("keeps boxes followed without a club in the bar, in order", () => {
    const entries = [
      { follow_id: "1", status: "active", box: box("a") },
      { follow_id: "2", status: "active", box: box("b") },
      { follow_id: "3", status: "requested", box: box("c") },
      { follow_id: "4", status: "active", person: { id: "p" } },
    ];
    const clubs = [{ kind: "gym", organization_id: "b" }, { kind: "open", organization_id: "a" }];
    expect(followedBoxBubbles(entries as never, clubs as never).map((entry) => entry.slug)).toEqual(["box-a"]);
  });
});
