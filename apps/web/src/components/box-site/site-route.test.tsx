import { isValidElement, type ReactElement, type ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { PublicSiteV2 } from "@/api/box-site";

import { BoxWebsite } from "./templates/BoxWebsite";
import { siteRouteTarget } from "./templates/site-route-target";
import { boxPage, boxSite, PACKAGES } from "./templates/site.test-fixtures";
import { SiteAudience } from "./SiteAudience";

const state = vi.hoisted(() => ({
  headers: new Map<string, string>(),
  cookies: {} as Record<string, string>,
  page: null as unknown,
  site: null as unknown,
  sites: {} as Record<string, unknown>,
}));

vi.mock("next/headers", () => ({
  headers: async () => ({ get: (name: string) => state.headers.get(name) ?? null }),
  cookies: async () => ({ get: (name: string) => (name in state.cookies ? { value: state.cookies[name] } : undefined) }),
}));
vi.mock("next/navigation", () => ({
  notFound: () => {
    throw new Error("NOT_FOUND");
  },
  redirect: (path: string) => {
    throw new Error(`REDIRECT ${path}`);
  },
  permanentRedirect: (path: string) => {
    throw new Error(`PERMANENT ${path}`);
  },
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock("next-intl/server", () => ({ getTranslations: async () => (key: string) => key }));
vi.mock("@/lib/site-url", () => ({ siteOrigin: async () => new URL("https://palee.app") }));
vi.mock("@/lib/public-box", () => ({ loadPublicBox: async () => state.page, previewLine: () => "CrossFit · Κυψέλη" }));
vi.mock("@/lib/public-site", async (original) => ({
  ...(await original<typeof import("@/lib/public-site")>()),
  loadPublicSite: async (_slug: string, lang?: string | null) => (lang ? (state.sites[lang] ?? null) : state.site),
  loadPublicPackages: async () => ({ packages: PACKAGES, online_payments: false }),
}));

import { SiteRoute, siteMetadata } from "./site-route";

/** The first element of a type anywhere in a server-rendered tree (children and element props). */
function find(node: ReactNode, type: unknown): ReactElement<Record<string, unknown>> | null {
  if (Array.isArray(node)) {
    for (const child of node) {
      const hit = find(child, type);
      if (hit) return hit;
    }
    return null;
  }
  if (!isValidElement(node)) return null;
  const element = node as ReactElement<Record<string, unknown>>;
  if (element.type === type) return element;
  for (const value of Object.values(element.props)) {
    const hit = find(value as ReactNode, type);
    if (hit) return hit;
  }
  return null;
}

const english = (site: PublicSiteV2) => ({ ...site, translation: "en" });

beforeEach(() => {
  state.headers = new Map();
  state.cookies = {};
  state.page = boxPage();
  const site = boxSite();
  state.site = site;
  state.sites = { en: english(site) };
});

describe("siteRouteTarget", () => {
  it("reads a page in the box's language, a translation, or both", () => {
    expect(siteRouteTarget("schedule")).toEqual({ language: "box", pageKey: "schedule" });
    expect(siteRouteTarget("en")).toEqual({ language: "en", pageKey: "home" });
    expect(siteRouteTarget("en", "Space")).toEqual({ language: "en", pageKey: "space" });
    expect(siteRouteTarget("pt-pt", "coaches")).toEqual({ language: "pt-PT", pageKey: "coaches" });
  });
  it("is a 404 for anything else", () => {
    expect(siteRouteTarget("chatroom")).toBeNull();
    expect(siteRouteTarget("en", "home")).toBeNull();
    expect(siteRouteTarget("schedule", "en")).toBeNull();
  });
});

describe("SiteRoute (ADR-530 pages)", () => {
  it("serves a sub-page to guests, with the app view kept for members", async () => {
    const tree = await SiteRoute({ slug: "box-kypseli", language: "box", pageKey: "schedule" });
    const audience = find(tree, SiteAudience);
    expect(audience).not.toBeNull();
    const website = find(audience!.props.website as ReactNode, BoxWebsite);
    expect(website?.props).toMatchObject({ pageKey: "schedule", basePath: "/b/box-kypseli", language: "box", standalone: false });
    expect(audience!.props.app).toBeTruthy();
  });

  it("sends a page with nothing on it home", async () => {
    state.site = boxSite({ sections: ["hero", "about", "packages"] as never });
    await expect(SiteRoute({ slug: "box-kypseli", language: "box", pageKey: "coaches" })).rejects.toThrow("REDIRECT /b/box-kypseli");
    state.sites = { en: english(boxSite({ sections: ["hero", "about"] as never })) };
    await expect(SiteRoute({ slug: "box-kypseli", language: "en", pageKey: "space" })).rejects.toThrow("REDIRECT /b/box-kypseli/en");
  });

  it("keeps the page when a first visit moves to the visitor's language", async () => {
    state.headers.set("accept-language", "en-GB,en;q=0.9");
    await expect(SiteRoute({ slug: "box-kypseli", language: "box", pageKey: "schedule" })).rejects.toThrow("REDIRECT /b/box-kypseli/en/schedule");
  });

  it("moves an old address of the box to its slug, page and language kept", async () => {
    await expect(SiteRoute({ slug: "old-name", language: "en", pageKey: "coaches" })).rejects.toThrow("PERMANENT /b/box-kypseli/en/coaches");
  });

  it("serves the website alone on the box's own domain", async () => {
    state.headers.set("x-palee-site-host", "www.boxkypseli.gr");
    const tree = await SiteRoute({ slug: "box-kypseli", language: "box", pageKey: "home" });
    expect(find(tree, SiteAudience)).toBeNull();
    expect(find(tree, BoxWebsite)?.props).toMatchObject({ basePath: "", standalone: true });
  });

  it("falls back to the given app view when the website does not show the page", async () => {
    state.site = boxSite({ sections: ["hero", "about"] as never });
    const sales = <p>sales</p>;
    const tree = await SiteRoute({ slug: "box-kypseli", language: "box", pageKey: "packages", appView: sales });
    expect(find(tree, BoxWebsite)).toBeNull();
    expect(find(tree, "p")).not.toBeNull();
  });

  it("is the box page alone, without sub-pages, when the box has no website", async () => {
    state.site = null;
    await expect(SiteRoute({ slug: "box-kypseli", language: "box", pageKey: "schedule" })).rejects.toThrow("REDIRECT /b/box-kypseli");
  });
});

describe("siteMetadata", () => {
  it("names the page, points canonical at it and lists every language's copy", async () => {
    const metadata = await siteMetadata("box-kypseli", "box", "schedule");
    expect(metadata.title).toBe("pages.schedule · Box Κυψέλη");
    expect(metadata.alternates?.canonical).toBe("https://palee.app/b/box-kypseli/schedule");
    expect(metadata.alternates?.languages).toEqual({
      el: "https://palee.app/b/box-kypseli/schedule",
      en: "https://palee.app/b/box-kypseli/en/schedule",
      "x-default": "https://palee.app/b/box-kypseli/schedule",
    });
  });

  it("uses the box's name alone on the home page and in a translation's canonical", async () => {
    const metadata = await siteMetadata("box-kypseli", "en", "home");
    expect(metadata.title).toBe("Box Κυψέλη");
    expect(metadata.alternates?.canonical).toBe("https://palee.app/b/box-kypseli/en");
  });

  it("describes a hidden page as the home page", async () => {
    state.site = boxSite({ sections: ["hero", "about"] as never });
    const metadata = await siteMetadata("box-kypseli", "box", "coaches");
    expect(metadata.title).toBe("Box Κυψέλη");
  });
});

