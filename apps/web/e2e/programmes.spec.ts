import { expect, test, type Page, type Route } from "./support/test";

// W8 / CP-D4 programme marketplace (ADR-370/371): the staff list of
// «Προγράμματα προπόνησης» with «Νέο πρόγραμμα», and the public
// «Αγορά προγραμμάτων» catalogue with its goal chips. The API is stubbed.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

type Write = { path: string; method: string; body: unknown };

const owner = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

function tokenFor(user: { id: string; role: string }) {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const membership = {
  role: "owner",
  roles: ["owner"],
  capabilities: { manage_settings: true, manage_members: true, message_from_box: true, view_analytics: true },
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", activation: "active", timezone: "Europe/Athens", timezone_confirmed: true },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

function staffProgramme(id: string, title: string, status: "draft" | "published", extra: Record<string, unknown> = {}) {
  return {
    id,
    title,
    status,
    draft_weeks: 6,
    price_cents: status === "published" ? 4900 : null,
    currency: "EUR",
    version: status === "published" ? { id: `${id}-v1`, number: 1, weeks: 6 } : null,
    reviews: { average: null, count: 0 },
    sales: { buyers: status === "published" ? 3 : 0 },
    ...extra,
  };
}

const marketplace = [
  {
    id: "p-strength",
    title: "Strength in 6 weeks",
    goal: "strength",
    level: "intermediate",
    weeks: 6,
    price_cents: 4900,
    currency: "EUR",
    rating_average: null,
    rating_count: 0,
    organization_name: "Box Kypseli",
    organization_slug: "kypseli",
  },
  {
    id: "p-engine",
    title: "Engine builder",
    goal: "endurance",
    level: "beginner",
    weeks: 8,
    price_cents: 3900,
    currency: "EUR",
    rating_average: 4.6,
    rating_count: 12,
    organization_name: "Box Pagrati",
    organization_slug: "pagrati",
  },
];

async function stubApi(page: Page, writes: Write[], extra?: (path: string, method: string, route: Route, url: URL) => Promise<void> | null) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const url = new URL(route.request().url());
    const path = tenantless(url.pathname);
    const method = route.request().method();
    if (method !== "GET") writes.push({ path: `${path}${url.search}`, method, body: route.request().postDataJSON() });
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(owner), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, owner);
    if (path === "/api/memberships") return json(route, [membership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/public/status") return json(route, { status: "operational", generated_at: new Date().toISOString(), components: [], active: [], upcoming: [] });
    const handled = extra?.(path, method, route, url);
    if (handled) return handled;
    return json(route, {});
  });
}

test.describe("programmes (staff)", () => {
  test("the list shows each programme with its status, and «New programme» creates a draft and opens it", async ({ page }) => {
    const writes: Write[] = [];
    await stubApi(page, writes, (path, method, route) => {
      if (path === "/api/admin/programmes" && method === "GET") {
        return json(route, { programmes: [staffProgramme("prog-1", "Strength in 6 weeks", "published"), staffProgramme("prog-2", "Summer engine", "draft")] });
      }
      if (path === "/api/admin/programmes" && method === "POST") {
        return json(route, { programme: staffProgramme("prog-3", "Gymnastics basics", "draft", { draft_weeks: 4 }) }, 201);
      }
      if (path === "/api/admin/programmes/prog-3") return json(route, { programme: staffProgramme("prog-3", "Gymnastics basics", "draft", { draft_weeks: 4 }) });
      return null;
    });
    await page.goto("/admin/programmes");

    await expect(page.getByRole("heading", { name: "Training programmes", level: 1 })).toBeVisible();
    await expect(page.getByTestId("programme-row-prog-1")).toContainText("Strength in 6 weeks");
    await expect(page.getByTestId("programme-row-prog-1")).toContainText("3 buyers");
    await expect(page.getByTestId("programme-row-prog-2")).toContainText("Summer engine");

    await page.getByRole("button", { name: "New programme" }).click();
    const dialog = page.getByTestId("programme-new-dialog");
    await dialog.getByLabel("Title").fill("Gymnastics basics");
    await dialog.getByRole("button", { name: "Create" }).click();

    await expect(page).toHaveURL(/\/admin\/programmes\/prog-3$/);
    const created = writes.find((write) => write.path === "/api/admin/programmes" && write.method === "POST");
    expect(created?.body).toEqual({ title: "Gymnastics basics", draft_weeks: 4 });
  });
});

test.describe("programme store (public)", () => {
  test("the catalogue lists programmes from every box, and a goal chip filters the list", async ({ page }) => {
    const queries: string[] = [];
    await stubApi(page, [], (path, _method, route, url) => {
      if (path === "/api/public/programmes") {
        queries.push(url.search);
        const goal = url.searchParams.get("goal");
        return json(route, { programmes: goal ? marketplace.filter((entry) => entry.goal === goal) : marketplace });
      }
      return null;
    });
    await page.goto("/programmes");

    await expect(page.getByRole("heading", { name: "Programme store", level: 1 })).toBeVisible();
    await expect(page.getByTestId("programme-card-p-strength")).toContainText("Box Kypseli");
    await expect(page.getByTestId("programme-card-p-engine")).toContainText("Box Pagrati");
    await expect(page.getByTestId("programme-card-p-strength").getByRole("link", { name: "See the programme" })).toHaveAttribute(
      "href",
      "/b/kypseli/programmes/p-strength",
    );

    await page.getByRole("radio", { name: "Endurance" }).click();
    await expect(page.getByTestId("programme-card-p-strength")).toHaveCount(0);
    await expect(page.getByTestId("programme-card-p-engine")).toBeVisible();
    expect(queries).toContain("?goal=endurance");
  });
});
