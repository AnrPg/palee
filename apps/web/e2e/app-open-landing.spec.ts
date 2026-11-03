import { expect, test, type Page } from "./support/test";

// W7 screen 12: a member of exactly one box opens the app on the Box tab;
// everyone else opens on Feed. Tapping Feed afterwards still shows Feed. The
// API is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const membership = (slug: string) => ({
  role: "member",
  roles: ["member"],
  capabilities: {},
  organization: { id: `org-${slug}`, slug, name: `Box ${slug}`, provider_kind: "gym", timezone: "UTC" },
  settings: { brand_name: `Box ${slug}`, brand_logo_url: null, brand_primary_color: null },
});

async function signedIn(page: Page, slugs: string[]) {
  const user = {
    id: "member-1",
    nickname: "Maria",
    role: "member",
    email: "maria@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: slugs.map((slug) => ({ organization_slug: slug, role: "member", settings: {} })),
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: slugs.map((slug) => ({ organization_slug: slug })), exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: `stub.${payload}.signature`, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json(slugs.map(membership))));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

test.describe("where the app opens", () => {
  test("a member of one box opens on the Box tab", async ({ page }) => {
    await signedIn(page, ["box1"]);
    await page.goto("/");
    await expect(page).toHaveURL(/\/box$/);
  });

  test("a member of two boxes opens on Feed", async ({ page }) => {
    await signedIn(page, ["box1", "box2"]);
    await page.goto("/");
    await expect(page.getByRole("navigation").first()).toBeVisible();
    await expect(page).toHaveURL(/\/$/);
  });
});
