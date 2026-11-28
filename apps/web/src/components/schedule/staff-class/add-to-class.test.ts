import { describe, expect, it } from "vitest";

import { mayAddToClass } from "./add-to-class";

describe("mayAddToClass (ADR-790)", () => {
  const slot = { coach_user_id: "coach-1" };

  it("lets staff who book for clients or manage the schedule add to any class", () => {
    expect(mayAddToClass({ role: "coach", capabilities: { book_for_clients: "all" } }, slot, "desk-1")).toBe(true);
    expect(mayAddToClass({ role: "coach", capabilities: { manage_schedule: "all" } }, slot, "owner-1")).toBe(true);
  });

  it("lets a coach add to the classes they run, and a head coach to any", () => {
    expect(mayAddToClass({ role: "coach", capabilities: { run_classes: "own" } }, slot, "coach-1")).toBe(true);
    expect(mayAddToClass({ role: "coach", capabilities: { run_classes: "own" } }, slot, "coach-2")).toBe(false);
    expect(mayAddToClass({ role: "coach", capabilities: { run_classes: "all" } }, slot, "coach-2")).toBe(true);
  });

  it("hides it from everyone else and while the membership loads", () => {
    expect(mayAddToClass({ role: "coach", capabilities: { check_in: "all" } }, slot, "coach-1")).toBe(false);
    expect(mayAddToClass(null, slot, "coach-1")).toBe(false);
  });
});
