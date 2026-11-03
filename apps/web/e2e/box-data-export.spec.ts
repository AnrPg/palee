import { expect, test, type Page } from "./support/test";

// ADR-365 / ADR-367, W7 screen 3: «Download the box's data» in Settings ›
// Business, between the ownership transfer and closing the box. Idle →
// «Prepare the file»; working → an email comes when it is ready; ready →
// «Download ZIP», photos and PDFs in extra parts, a new file tomorrow. The
// closing card links to it. The API is stubbed; every route not listed
// answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

async function signedInOwner(page: Page) {
  const user = {
    id: "owner-1",
    nickname: "Apostolos",
    role: "member",
    email: "apostolos@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role: "owner", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.addInitScript(() => {
    window.localStorage.setItem("palee:selected-organization-slug", "box1");
    window.localStorage.setItem("palee.view", "staff");
  });
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: `stub.${payload}.signature`, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "owner",
          roles: ["owner"],
          capabilities: { manage_settings: "all", manage_organization_lifecycle: "all" },
          organization: { id: "org-1", slug: "box1", name: "Box One", provider_kind: "gym", timezone: "UTC" },
          settings: { brand_name: "Box One", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

const pending = {
  id: "e1",
  status: "pending",
  record_count: null,
  table_count: null,
  requested_at: new Date().toISOString(),
  completed_at: null,
  expires_at: null,
  file: null,
  parts: [],
};

const ready = {
  ...pending,
  status: "ready",
  record_count: 1200,
  table_count: 80,
  completed_at: new Date().toISOString(),
  expires_at: new Date(Date.now() + 7 * 86_400_000).toISOString(),
  file: { name: "palee-box1-data.zip", bytes: 4_000_000, sha256: "x", download_url: "https://objects.test/data.zip" },
  parts: [{ name: "palee-box1-files-1.zip", bytes: 180_000_000, sha256: "y", files: 120, download_url: "https://objects.test/files-1.zip" }],
};

test.describe("Settings › Business › Download the box's data", () => {
  test("idle → working: one button, then the email it will come to", async ({ page }) => {
    await signedInOwner(page);
    let exports: unknown[] = [];
    await page.route("**/api/org/box1/admin/data-exports", (route) => {
      if (route.request().method() === "POST") {
        exports = [pending];
        return route.fulfill(json(pending, 202));
      }
      return route.fulfill(json({ exports }));
    });

    await page.goto("/admin/settings#organization");
    const card = page.getByTestId("box-data-export");
    await expect(card).toHaveAttribute("data-state", "idle");
    await expect(card).toContainText("Last file: none.");
    await card.getByRole("button", { name: "Prepare the file" }).click();
    await expect(card).toHaveAttribute("data-state", "working");
    await expect(card).toContainText("We will email apostolos@example.com when it is ready");
  });

  test("ready: «Download ZIP», the photo parts and a new file tomorrow; closing the box links here", async ({ page }) => {
    await signedInOwner(page);
    await page.route("**/api/org/box1/admin/data-exports", (route) => route.fulfill(json({ exports: [ready] })));

    await page.goto("/admin/settings#organization");
    const card = page.getByTestId("box-data-export");
    await expect(card.getByTestId("box-data-export-download")).toHaveAttribute("href", "https://objects.test/data.zip");
    await expect(card.getByTestId("box-data-export-parts")).toContainText("Photos and PDFs are in 1 more ZIP file:");
    await expect(card).toContainText("You can ask for a new file tomorrow.");
    await expect(page.getByRole("link", { name: "Before you close it, download the box's data ↑" })).toHaveAttribute("href", "#box-data-export");
  });
});
