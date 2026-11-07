import { describe, expect, it } from "vitest";

import { joinBoxTarget } from "./join-box";

const box = { organization_id: "org-1", slug: "kypseli", name: "Kypseli", logo_url: null, primary_color: null };

describe("joinBoxTarget", () => {
  it("leads to the packages when the box lists any", () => {
    expect(joinBoxTarget({ box, joining: { packages: true, join_link: true } }, true)).toEqual({ kind: "link", href: "/b/kypseli/packages" });
  });

  it("leads to the member join link when there are no packages", () => {
    expect(joinBoxTarget({ box, joining: { packages: false, join_link: true } }, false)).toEqual({ kind: "link", href: "/join/kypseli" });
  });

  it("asks the box otherwise, after signing in when needed", () => {
    const none = { box, joining: { packages: false, join_link: false } };
    expect(joinBoxTarget(none, true)).toEqual({ kind: "ask" });
    expect(joinBoxTarget(none, false)).toEqual({ kind: "link", href: `/login?next=${encodeURIComponent("/b/kypseli?join=1")}` });
  });
});
