import { describe, expect, it } from "vitest";

import { boxVoice } from "./PostCard";

const club = { id: "c1", kind: "gym", name: "Milos Method", organization_slug: "milos-method", logo_url: "https://x/logo.png", primary_color: null };

describe("boxVoice (ADR-590)", () => {
  it("heads a public club post with the box, linking its page", () => {
    expect(boxVoice({ origin: "club", audience: "public", club } as never)).toEqual({
      name: "Milos Method",
      logo: "https://x/logo.png",
      href: "/b/milos-method",
    });
  });

  it("leaves channel posts, profile posts and open clubs to their author", () => {
    expect(boxVoice({ origin: "club", audience: "club_channel", club } as never)).toBeNull();
    expect(boxVoice({ origin: "profile", audience: "public", club: null } as never)).toBeNull();
    expect(boxVoice({ origin: "club", audience: "public", club: { ...club, kind: "open" } } as never)).toBeNull();
    expect(boxVoice({ origin: "club", audience: "public", club: { ...club, organization_slug: null } } as never)).toBeNull();
  });
});
