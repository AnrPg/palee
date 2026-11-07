import { afterEach, describe, expect, test, vi } from "vitest";

import { loadPublicBox } from "@/lib/public-box";

afterEach(() => vi.unstubAllGlobals());

describe("loadPublicBox", () => {
  // The API forces https and only trusts x-forwarded-proto; a plain cluster
  // http call without it is answered with a 301 to https://palee-api, which
  // nothing serves, and the box page fails with a 500.
  test("tells the API the request came over https", async () => {
    const fetchMock = vi.fn(async () => new Response(null, { status: 404 }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(loadPublicBox("milos-method")).resolves.toBeNull();

    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toMatch(/\/api\/public\/boxes\/milos-method$/);
    expect(init.headers).toMatchObject({ "x-forwarded-proto": "https" });
  });
});
