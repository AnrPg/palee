import { describe, expect, it } from "vitest";

import type { Lead } from "@/api/leads";

import { canMoveTo, columns, dueState, eventLine, initials, splitContact, stageCount, telHref, validateEnquiry, validateLeadForm } from "./lead-model";

const now = new Date("2027-05-10T10:00:00Z");
const zone = "Europe/Athens";

function lead(id: string, stage: Lead["stage"], created_at: string, due_at?: string): Lead {
  return {
    id,
    stage,
    created_at,
    next_task: due_at ? { id: `t-${id}`, title: "Call", due_at, done_at: null } : null,
  } as unknown as Lead;
}

describe("dueState", () => {
  it("tells late, today, later and none apart in the gym's zone", () => {
    expect(dueState({ due_at: "2027-05-10T09:00:00Z", done_at: null }, now, zone)).toBe("late");
    expect(dueState({ due_at: "2027-05-10T18:00:00Z", done_at: null }, now, zone)).toBe("today");
    // 22:30 UTC is already the next day in Athens.
    expect(dueState({ due_at: "2027-05-10T22:30:00Z", done_at: null }, now, zone)).toBe("later");
    expect(dueState({ due_at: "2027-05-09T09:00:00Z", done_at: "2027-05-09T10:00:00Z" }, now, zone)).toBe("none");
    expect(dueState(null, now, zone)).toBe("none");
  });
});

describe("columns", () => {
  it("puts each open lead in its column, most urgent first", () => {
    const result = columns(
      [
        lead("a", "new", "2027-05-01T00:00:00Z"),
        lead("b", "new", "2027-05-02T00:00:00Z", "2027-05-09T08:00:00Z"),
        lead("c", "trial", "2027-05-03T00:00:00Z"),
        lead("d", "lost", "2027-05-03T00:00:00Z"),
        lead("e", "new", "2027-05-05T00:00:00Z"),
      ],
      now,
      zone,
    );
    expect(result.map((column) => column.stage)).toEqual(["new", "trial", "offer"]);
    expect(result[0].leads.map((entry) => entry.id)).toEqual(["b", "e", "a"]);
    expect(result[1].leads.map((entry) => entry.id)).toEqual(["c"]);
    expect(result[2].leads).toEqual([]);
  });
});

describe("stageCount", () => {
  it("adds the open stages and reads zero for the missing ones", () => {
    const counts = { new: 4, trial: 2, offer: 1, lost: 3 };
    expect(stageCount(counts, "open")).toBe(7);
    expect(stageCount(counts, "lost")).toBe(3);
    expect(stageCount(counts, "converted")).toBe(0);
    expect(stageCount(undefined, "new")).toBe(0);
  });
});

describe("canMoveTo", () => {
  it("never moves to or from «converted» by hand", () => {
    expect(canMoveTo({ stage: "new" }, "trial")).toBe(true);
    expect(canMoveTo({ stage: "new" }, "new")).toBe(false);
    expect(canMoveTo({ stage: "new" }, "converted")).toBe(false);
    expect(canMoveTo({ stage: "converted" }, "new")).toBe(false);
    expect(canMoveTo({ stage: "lost" }, "new")).toBe(true);
  });
});

describe("initials", () => {
  it("takes the first letters of the first and last name, Greek too", () => {
    expect(initials("Μαρία Παπαδοπούλου")).toBe("ΜΠ");
    expect(initials("anna")).toBe("AN");
    expect(initials("  ")).toBe("?");
  });
});

describe("validateLeadForm", () => {
  it("needs a name and a phone or an email", () => {
    expect(validateLeadForm({ name: "", email: "", phone: "" })).toEqual({ name: "required", contact: "required" });
    expect(validateLeadForm({ name: "Anna", email: "", phone: "6900000000" })).toEqual({});
    expect(validateLeadForm({ name: "Anna", email: "anna@", phone: "" })).toEqual({ email: "invalid" });
  });
});

describe("validateEnquiry", () => {
  it("needs a name, a reachable contact and the contact consent", () => {
    expect(validateEnquiry({ name: "", contact: "", consent: false })).toEqual({ name: "required", contact: "required", consent: "required" });
    expect(validateEnquiry({ name: "Anna", contact: "12", consent: true })).toEqual({ contact: "invalid" });
    expect(validateEnquiry({ name: "Anna", contact: "a@b", consent: true })).toEqual({ contact: "invalid" });
    expect(validateEnquiry({ name: "Anna", contact: "+30 690 000 0000", consent: true })).toEqual({});
  });
});

describe("splitContact", () => {
  it("sends an email or a phone", () => {
    expect(splitContact(" anna@example.com ")).toEqual({ email: "anna@example.com" });
    expect(splitContact("6900000000")).toEqual({ phone: "6900000000" });
    expect(splitContact("")).toEqual({});
  });
});

describe("eventLine", () => {
  it("maps history events to their message keys", () => {
    expect(eventLine({ kind: "stage_changed", data: { to: "lost", lost_reason: "price" } })).toEqual({ key: "lost", values: { reason: "price" } });
    expect(eventLine({ kind: "stage_changed", data: { to: "trial" } })).toEqual({ key: "stage_changed", values: { stage: "trial" } });
    expect(eventLine({ kind: "contacted", data: { channel: "in_person" } })).toEqual({ key: "contacted", values: { channel: "in_person" } });
    expect(eventLine({ kind: "created", data: { source: "form" } })).toEqual({ key: "created", values: { source: "form" } });
    expect(eventLine({ kind: "converted", data: null } as never)).toEqual({ key: "converted", values: {} });
  });
});

describe("telHref", () => {
  it("dials only a real number", () => {
    expect(telHref("+30 690 000 0000")).toBe("tel:+306900000000");
    expect(telHref("12")).toBeNull();
    expect(telHref(null)).toBeNull();
  });
});
