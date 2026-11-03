import { describe, expect, it, vi } from "vitest";

import { isAppHost, isSitePath, lookupSiteHost, siteRewritePath } from "./site-host";

describe("box website on its own domain", () => {
  it("never looks up the app's own hosts", () => {
    expect(isAppHost("localhost:3000", {})).toBe(true);
    expect(isAppHost("127.0.0.1", {})).toBe(true);
    expect(isAppHost("palee.app", {})).toBe(true);
    expect(isAppHost("staging.palee.app", {})).toBe(true);
    expect(isAppHost("preview.example.net", { PALEE_APP_HOSTS: "preview.example.net" })).toBe(true);
    expect(isAppHost("app.example.org", { NEXT_PUBLIC_SITE_URL: "https://app.example.org" })).toBe(true);
    expect(isAppHost("status.example.org", { STATUS_HOST: "status.example.org" })).toBe(true);
    expect(isAppHost("www.mybox.gr", {})).toBe(false);
  });

  it("serves only the site's pages from the domain root", () => {
    expect(siteRewritePath("/", "kypseli")).toBe("/b/kypseli");
    expect(siteRewritePath("/en", "kypseli")).toBe("/b/kypseli/en");
    expect(siteRewritePath("/privacy", "kypseli")).toBe("/b/kypseli/privacy");
    expect(siteRewritePath("/packages/", "kypseli")).toBe("/b/kypseli/packages");
    expect(siteRewritePath("/_next/static/x.js", "kypseli")).toBeNull();
    expect(siteRewritePath("/admin", "kypseli")).toBeNull();
  });

  it("allows the tags' origins only on website pages", () => {
    expect(isSitePath("/b/kypseli")).toBe(true);
    expect(isSitePath("/b/kypseli/en")).toBe(true);
    expect(isSitePath("/b/kypseli/chat")).toBe(false);
    expect(isSitePath("/admin")).toBe(false);
  });

  it("asks the API once per host and remembers unknown hosts briefly", async () => {
    const cache = new Map();
    const fetchImpl = vi.fn(async (url: string) =>
      url.endsWith("/www.mybox.gr")
        ? new Response(JSON.stringify({ host: "www.mybox.gr", slug: "kypseli", primary: true, primary_host: "www.mybox.gr" }), { status: 200 })
        : new Response("{}", { status: 404 }),
    ) as unknown as typeof fetch;
    const now = () => 1_000;
    expect(await lookupSiteHost("www.mybox.gr:443", { apiOrigin: "http://api", fetchImpl, now, cache })).toEqual({ slug: "kypseli", primary: true, primaryHost: "www.mybox.gr" });
    await lookupSiteHost("WWW.mybox.gr", { apiOrigin: "http://api", fetchImpl, now, cache });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(await lookupSiteHost("unknown.gr", { apiOrigin: "http://api", fetchImpl, now, cache })).toBeNull();
  });
});
