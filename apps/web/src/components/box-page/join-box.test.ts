import { describe, expect, it } from "vitest";

import { joinBoxHref } from "./join-box";

const box = { organization_id: "org-1", slug: "kypseli", name: "Kypseli", logo_url: null, primary_color: null };

describe("joinBoxHref", () => {
  it("leads to the packages when the box lists any", () => {
    expect(joinBoxHref({ box, joining: { packages: true, join_link: true } }, true)).toBe("/b/kypseli/packages");
  });

  it("leads to the member join link when there are no packages", () => {
    expect(joinBoxHref({ box, joining: { packages: false, join_link: true } }, false)).toBe("/join/kypseli");
  });

  it("opens the chat with a message ready otherwise, after signing in when needed", () => {
    const none = { box, joining: { packages: false, join_link: false } };
    expect(joinBoxHref(none, true)).toBe("/b/kypseli/chat?draft=member");
    expect(joinBoxHref(none, false)).toBe(`/login?next=${encodeURIComponent("/b/kypseli/chat?draft=member")}`);
  });
});
