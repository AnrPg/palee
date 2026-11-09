import { describe, expect, it } from "vitest";

import type { FollowSuggestionReason } from "@/api/follow-suggestions";

import { reasonMessage } from "./follow-suggestions-model";

const base: FollowSuggestionReason = { kind: "for_you", mutual_count: 0, mutuals: [] };
const sport = (key: string) => (key === "crossfit" ? "CrossFit" : null);

describe("reasonMessage", () => {
  it("names up to two common follows and counts the rest", () => {
    const reason: FollowSuggestionReason = {
      ...base,
      kind: "mutual",
      mutual_count: 4,
      mutuals: [
        { id: "1", nickname: "Μαρία" },
        { id: "2", nickname: "Νίκος" },
      ],
    };
    expect(reasonMessage(reason, sport)).toEqual({ key: "reason.mutual", values: { names: "Μαρία, Νίκος", more: 2 } });
    expect(reasonMessage({ ...reason, mutuals: [] }, sport)).toEqual({ key: "reason.mutualCount", values: { count: 4 } });
  });

  it("says the box, the coach and the newcomer's box by name", () => {
    const box = { id: "b", name: "Milos method" };
    expect(reasonMessage({ ...base, kind: "box", box }, sport)).toEqual({ key: "reason.box", values: { box: "Milos method" } });
    expect(reasonMessage({ ...base, kind: "coach", box }, sport)).toEqual({ key: "reason.coach", values: { box: "Milos method" } });
    expect(reasonMessage({ ...base, kind: "newcomer", box }, sport).key).toBe("reason.newInBox");
    expect(reasonMessage({ ...base, kind: "newcomer" }, sport).key).toBe("reason.newOnPalee");
  });

  it("names a known discipline and stays generic for an unknown one", () => {
    expect(reasonMessage({ ...base, kind: "sport", sport: "crossfit" }, sport)).toEqual({ key: "reason.sport", values: { sport: "CrossFit" } });
    expect(reasonMessage({ ...base, kind: "sport", sport: "new_thing" }, sport).key).toBe("reason.sports");
  });

  it("uses the profile's name for «Και αυτοί ίσως» and falls back without it", () => {
    expect(reasonMessage({ ...base, kind: "via_person" }, sport, "Ελένη")).toEqual({ key: "reason.viaPerson", values: { name: "Ελένη" } });
    expect(reasonMessage({ ...base, kind: "via_person" }, sport).key).toBe("reason.forYou");
    expect(reasonMessage({ ...base, kind: "follows_you" }, sport).key).toBe("reason.followsYou");
  });
});
