import { expect, test, type Page, type Route } from "./support/test";

// Ρυθμίσεις › Τύποι τμημάτων (ADR-490): «Εκδήλωση» lives under «Προχωρημένα»,
// «Επίπεδο» takes several levels, and every advanced option has a tooltip and
// an info box a press opens. The API is stubbed; anything not stubbed answers `{}`.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

const USER = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "el",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: USER.id, role: "admin", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const MEMBERSHIP = {
  role: "owner",
  roles: ["owner"],
  capabilities: { manage_settings: true, manage_billing: true, take_payments: "all", view_finance_reports: true },
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", timezone: "Europe/Athens", timezone_confirmed: true },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

type ClassType = Record<string, unknown> & { id: string; kind: string; levels: string[] };

type Write = { method: string; path: string; body: unknown };

async function stub(page: Page, writes: Write[]) {
  const types: ClassType[] = [
    { id: "ct-bb", name: "Bodybuilding", slug: "bodybuilding", sort_order: 0, archived_at: null, credit_cost: 1, kind: "class", levels: [], audiences: [] },
    { id: "ct-cf", name: "CrossFit", slug: "crossfit", sort_order: 1, archived_at: null, credit_cost: 1, kind: "event", levels: ["beginner"], audiences: [] },
  ];

  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    const body = method === "GET" || method === "DELETE" ? null : route.request().postDataJSON();
    if (method !== "GET") writes.push({ method, path, body });
    if (path === "/api/auth/refresh") return json(route, { access_token: token(), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, USER);
    if (path === "/api/memberships") return json(route, [MEMBERSHIP]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/join-link") return json(route, { member: { enabled: false }, athlete: { enabled: false, key: null } });
    if (path === "/api/admin/settings") return json(route, { gamification: {}, finance: { subscription_grace_days: 7 }, scheduling: {} });
    if (path === "/api/admin/class-types") return json(route, { class_types: types });
    const one = path.match(/^\/api\/admin\/class-types\/([^/]+)$/);
    if (one && method === "PATCH") {
      const type = types.find((candidate) => candidate.id === one[1])!;
      Object.assign(type, body as object);
      return json(route, { class_type: type });
    }
    if (path === "/api/admin/locations") return json(route, { locations: [] });
    if (path === "/api/staff/members") return json(route, { staff: [] });
    return json(route, {});
  });
}

test("«Εκδήλωση» sits under «Προχωρημένα» and «Επίπεδο» takes several levels (ADR-490)", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, writes);
  await page.goto("/admin/settings#class-types");

  const section = page.locator("#class-types");
  const crossfit = section.locator("div").filter({ has: page.getByText("CrossFit", { exact: true }) }).last();
  await expect(section.getByText("CrossFit", { exact: true })).toBeVisible();

  // Closed: no checkbox on the card, but an event shows its badge.
  await expect(section.getByRole("checkbox", { name: "Εκδήλωση" })).toHaveCount(0);
  await expect(crossfit.getByText("Εκδήλωση")).toBeVisible();

  await crossfit.getByRole("button", { name: /Προχωρημένα/ }).click();
  await expect(crossfit.getByRole("checkbox", { name: "Εκδήλωση" })).toBeChecked();

  const levels = crossfit.getByRole("group", { name: "Επίπεδο" });
  await expect(levels.getByRole("button", { name: "Αρχάριοι" })).toHaveAttribute("aria-pressed", "true");
  await levels.getByRole("button", { name: "Μεσαίοι" }).click();
  await expect.poll(() => writes.find((w) => w.method === "PATCH")?.body).toMatchObject({ levels: ["beginner", "intermediate"] });
});

test("every advanced option explains itself: tooltip on hover, info box on press", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, writes);
  await page.goto("/admin/settings#class-types");

  const section = page.locator("#class-types");
  const card = section.locator("div").filter({ has: page.getByText("Bodybuilding", { exact: true }) }).last();
  await card.getByRole("button", { name: /Προχωρημένα/ }).click();

  const info = card.getByRole("button", { name: "Τι είναι το «Επίπεδο»;" });
  await info.click();
  const note = card.getByRole("note");
  await expect(note).toContainText("Τι κάνει:");
  await expect(note).toContainText("Τι βλέπουν τα μέλη:");
  await expect(note).toContainText("Πότε να το αλλάξεις:");
  await info.click();
  await expect(card.getByRole("note")).toHaveCount(0);

  await expect(card.getByRole("button", { name: /^Τι είναι το «/ })).toHaveCount(4);
  expect(writes.filter((w) => w.path.startsWith("/api/admin/class-types"))).toEqual([]);
});
