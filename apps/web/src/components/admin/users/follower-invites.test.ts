import { describe, expect, it } from "vitest";

import { followerRowState, selectableIds, toggleAll } from "./follower-invites";

const row = (id: string, invitable: boolean, status: "sent" | "declined" | null = null) => ({
  person: { id, nickname: id, handle: null, avatar_url: null },
  invitable,
  invite: status ? { status, sent_at: "2026-11-01T10:00:00Z", next_invite_at: null } : null,
});

describe("follower invites", () => {
  it("tells invitable, sent and declined rows apart", () => {
    expect(followerRowState(row("a", true))).toBe("invitable");
    expect(followerRowState(row("b", false, "sent"))).toBe("sent");
    expect(followerRowState(row("c", false, "declined"))).toBe("declined");
    // 90 days after a sent invitation the row is invitable again.
    expect(followerRowState(row("d", true, "sent"))).toBe("invitable");
  });

  it("only offers people who may be invited now", () => {
    expect(selectableIds([row("a", true), row("b", false, "sent"), row("c", false, "declined")])).toEqual(["a"]);
  });

  it("picks all on screen up to the limit, and clears them again", () => {
    const picked = toggleAll(new Set(), ["a", "b", "c"], 2);
    expect([...picked]).toEqual(["a", "b"]);
    const all = toggleAll(new Set(), ["a", "b"], 200);
    expect([...toggleAll(all, ["a", "b"], 200)]).toEqual([]);
  });
});
