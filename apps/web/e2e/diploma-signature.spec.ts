import { expect, test, type Page, type Request } from "./support/test";

// ADR-377 addendum (option Γ): Settings › «Signature for diplomas». A coach
// uploads a signature, sees it above their name line, and removes it; a
// member has no such section. The API is stubbed; every route not listed
// answers an empty object, which the section reads as "not a coach".

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

// A 1×1 transparent PNG.
const PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
  "base64",
);

const limits = { max_bytes: 524288, content_types: ["image/jpeg", "image/png"], min_width: 60, min_height: 20, max_width: 1600, max_height: 800 };

async function signedIn(page: Page, role: string) {
  const user = {
    id: "coach-1",
    nickname: "Nikos",
    display_name: "Nikos P.",
    handle: "nikos",
    role: "member",
    email: "nikos@example.com",
    email_verified: true,
    profile_count: 1,
    profile_limit: 3,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role, settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const token = `stub.${payload}.signature`;
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.addInitScript(() => {
    window.localStorage.setItem("palee:selected-organization-slug", "box1");
    window.localStorage.setItem("palee.view", "client");
  });
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role,
          roles: [role],
          capabilities: {},
          location_scope: null,
          organization: { id: "org-1", slug: "box1", name: "Box One", provider_kind: "gym", timezone: "UTC", activation: "active" },
          settings: { brand_name: "Box One", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [], unread_count: 0 })));
}

test.describe("Settings › Signature for diplomas", () => {
  test("a coach uploads a signature, sees it on the name line, and removes it", async ({ page }) => {
    await signedIn(page, "coach");
    let signature: Record<string, unknown> | null = null;
    const uploads: string[] = [];

    await page.route("**/api/me/diploma-signature/image", (route) =>
      signature ? route.fulfill({ status: 200, contentType: "image/png", body: PNG }) : route.fulfill(json({ code: "not_found" }, 404)),
    );
    await page.route("**/api/me/diploma-signature", (route) => {
      const request = route.request() as Request;
      if (request.method() === "POST") {
        uploads.push((request.postDataJSON() as { image_base64: string }).image_base64);
        signature = { id: "s-1", content_type: "image/png", byte_size: PNG.length, width: 1, height: 1, updated_at: "2026-11-03T10:00:00Z" };
        return route.fulfill(json({ signature }));
      }
      if (request.method() === "DELETE") {
        signature = null;
        return route.fulfill({ status: 204, body: "" });
      }
      return route.fulfill(json({ eligible: true, signature, limits }));
    });

    await page.goto("/me/settings#diploma-signature");
    const section = page.locator("#diploma-signature");
    await expect(section.getByText("No signature yet. Diplomas show an empty line above your name.")).toBeVisible();

    await section.getByLabel("Signature image").setInputFiles({ name: "signature.png", mimeType: "image/png", buffer: PNG });

    await expect.poll(() => uploads.length).toBe(1);
    expect(uploads[0]).toMatch(/^data:image\/png;base64,/);
    await expect(section.getByRole("img", { name: "Your signature" })).toBeVisible();
    await expect(section.getByText("Nikos P. · Coach")).toBeVisible();

    await section.getByRole("button", { name: "Remove" }).click();
    await expect(section.getByText("No signature yet. Diplomas show an empty line above your name.")).toBeVisible();
    await expect(section.getByRole("button", { name: "Upload signature" })).toBeVisible();
  });

  test("a file that is not an image shows the error under the field and is not sent", async ({ page }) => {
    await signedIn(page, "coach");
    let posted = false;
    await page.route("**/api/me/diploma-signature", (route) => {
      if ((route.request() as Request).method() === "POST") posted = true;
      return route.fulfill(json({ eligible: true, signature: null, limits }));
    });

    await page.goto("/me/settings#diploma-signature");
    const section = page.locator("#diploma-signature");
    await section.getByLabel("Signature image").setInputFiles({ name: "signature.gif", mimeType: "image/gif", buffer: Buffer.from("GIF89a") });

    await expect(section.getByText("Choose a PNG, JPEG or WebP image.")).toBeVisible();
    expect(posted).toBe(false);
  });

  test("a member does not award ranks, so the section is hidden", async ({ page }) => {
    await signedIn(page, "member");
    await page.goto("/me/settings");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await expect(page.locator("#diploma-signature")).toHaveCount(0);
  });
});
