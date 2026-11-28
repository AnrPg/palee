import { expect, test, type Page, type Route } from "./support/test";

// «Πωλείται online» (pilot mockup p1, option A; ADR-271): connecting online
// payments put the paid subscription packages on sale and the owner is told
// once in Ρυθμίσεις › Πληρωμές; each package says whether box members see it
// online, and the switch lives in the package's «Προχωρημένες ρυθμίσεις».
// Mockup 2026-11-28 (1A + 2A): «Διαθέσιμο» and «Ποιος το βλέπει» sit at the
// top of the package, and each package's eye in the list opens its sheet.
// The API is stubbed; anything not stubbed answers `{}`.

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
  capabilities: { manage_settings: true, manage_billing: true, manage_packages: true, take_payments: "all", view_finance_reports: true },
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", timezone: "Europe/Athens", timezone_confirmed: true },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

const OPTIONS = {
  purposes: { packages: true, autopay: true, drop_in: true, shop: true, personal_training: false },
  notify_member: true,
  notify_staff: true,
};

type Package = Record<string, unknown> & { id: string; sold_online: boolean; online_visibility: string };

const PACKAGES: Package[] = [
  { id: "p-unl", name: "Unlimited", package_type: "membership", billing_period: "monthly", base_price_cents: 7500, active: true, sold_online: true, online_visibility: "visible" },
  { id: "p-pt", name: "10 προσωπικές προπονήσεις", package_type: "pt_pack", billing_period: "one_off", base_price_cents: 35000, active: true, sold_online: true, online_visibility: "purpose_off" },
  { id: "p-w3", name: "3 φορές την εβδομάδα", package_type: "membership", billing_period: "monthly", base_price_cents: 6000, active: true, sold_online: false, online_visibility: "off" },
  { id: "p-trial", name: "Δοκιμαστικό 7 ημερών", package_type: "trial", billing_period: "one_off", base_price_cents: 0, active: true, sold_online: false, online_visibility: "free" },
];

type Write = { method: string; path: string; body: unknown };

async function stub(page: Page, writes: Write[]) {
  const packages = PACKAGES.map((pkg) => ({ ...pkg }));
  let audience = "all";
  let featured: string | null = null;
  let notice: { count: number; opened_at: string } | null = { count: 2, opened_at: "2027-03-10T09:00:00Z" };
  const status = () => ({
    account: {
      id: "acc-1",
      provider: "viva",
      environment: "live",
      status: "active",
      settings: {},
      credentials_set: ["client_id", "client_secret", "merchant_id", "api_key"],
      webhook_url: "https://palee.app/api/webhooks/payments/org-1/acc-1",
      options: OPTIONS,
      connection: "platform",
      packages_notice: notice,
    },
    providers: ["viva", "stripe"],
    environments: ["test", "live"],
    connect_providers: { live: ["stripe"], test: [] },
    online_sales: { sold_online: packages.filter((pkg) => pkg.sold_online && Number(pkg.base_price_cents) > 0).length, packages: 3 },
  });

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
    if (path === "/api/admin/payments/account/packages-notice" && method === "DELETE") {
      notice = null;
      return json(route, status());
    }
    if (path === "/api/admin/payments/account") return json(route, status());
    if (path === "/api/admin/payments/attention") return json(route, { payments: [], total: 0 });
    if (path === "/api/admin/class-types") return json(route, { class_types: [] });
    if (path === "/api/admin/locations") return json(route, { locations: [] });
    if (path === "/api/staff/members") return json(route, { staff: [] });
    if (path === "/api/admin/package-audience") {
      if (method === "PUT") audience = (body as { audience: string }).audience;
      return json(route, { audience, exceptions: [], featured_package_id: featured });
    }
    const own = path.match(/^\/api\/admin\/package-audience\/packages\/([^/]+)$/);
    if (own && method === "PUT") {
      const pkg = packages.find((candidate) => candidate.id === own[1]);
      if (pkg) pkg.audience = (body as { audience: string | null }).audience;
      return json(route, { id: own[1], audience: pkg?.audience ?? null });
    }
    const retire = path.match(/^\/api\/admin\/finance\/packages\/([^/]+)\/retire$/);
    if (retire && method === "PATCH") {
      const pkg = packages.find((candidate) => candidate.id === retire[1]);
      if (pkg) pkg.active = false;
      return json(route, { package: pkg, reassigned_count: 0, affected_by_role: {} });
    }
    if (path === "/api/admin/package-audience/featured" && method === "PUT") {
      featured = (body as { package_id: string | null }).package_id;
      return json(route, { audience, exceptions: [], featured_package_id: featured });
    }
    if (path === "/api/admin/finance/package-catalog") return json(route, { version: 2, implemented_phases: [], modules: [], sections: [], fields: [], types: [] });
    if (path === "/api/admin/finance/packages") return json(route, { packages });
    const one = path.match(/^\/api\/admin\/finance\/packages\/([^/]+)$/);
    if (one) {
      const pkg = packages.find((candidate) => candidate.id === one[1]);
      if (!pkg) return json(route, { code: "not_found" }, 404);
      if (method === "PATCH") {
        const patch = body as Record<string, unknown>;
        Object.assign(pkg, patch);
        if ("sold_online" in patch) pkg.online_visibility = pkg.sold_online ? "visible" : "off";
      }
      return json(route, { package: pkg });
    }
    if (path === "/api/admin/finance/queues") return json(route, { queues: {} });
    if (path.startsWith("/api/admin/finance/members")) return json(route, { members: [], meta: {} });
    return json(route, {});
  });
}

test("Payments tells the owner once what connecting put on sale and counts N of M", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, writes);
  await page.goto("/admin/settings?tab=payments");

  const notice = page.getByTestId("packages-opened-notice");
  await expect(notice).toContainText("Τα 2 πακέτα συνδρομής σου πωλούνται τώρα online.");
  await expect(notice.getByRole("link", { name: "Αλλαγή" })).toHaveAttribute("href", /\/admin\/finance\?tab=packages$/);

  const nudge = page.getByTestId("sold-online-nudge");
  await expect(nudge).toContainText("Πωλούνται online: 2 από 3 πακέτα συνδρομής");
  await expect(nudge.getByRole("link", { name: /Πακέτα συνδρομής/ })).toBeVisible();

  await notice.getByRole("button", { name: "Κλείσιμο" }).click();
  await expect(page.getByTestId("packages-opened-notice")).toHaveCount(0);
  expect(writes.some((w) => w.method === "DELETE" && w.path === "/api/admin/payments/account/packages-notice")).toBe(true);
});

test("each subscription package says whether it is sold online, and the switch lives in its advanced settings", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, writes);
  await page.goto("/admin/finance?tab=packages");

  const row = (name: RegExp) => page.getByTestId("package-row").filter({ hasText: name });
  await expect(row(/Unlimited/).getByTestId("sold-online-badge")).toHaveText("Online");
  await expect(row(/10 προσωπικές προπονήσεις/).getByTestId("sold-online-badge")).toHaveText("Online · δεν φαίνεται");
  await expect(row(/3 φορές την εβδομάδα/).getByTestId("sold-online-badge")).toHaveCount(0);
  await expect(page.getByTestId("sold-online-summary")).toContainText("Πωλούνται online: 2 από 3");

  // Why the personal-training package is not visible, with the fix.
  await page.getByRole("button", { name: /10 προσωπικές προπονήσεις/ }).click();
  await page.getByTestId("package-advanced").locator("summary").click();
  const card = page.getByTestId("sold-online-card");
  await expect(card.getByTestId("sold-online-hint")).toContainText("κλειστό στο «Τι πληρώνεται online»");
  await expect(card.getByRole("link", { name: /Άνοιξέ το/ })).toHaveAttribute("href", /\/admin\/settings\?tab=payments$/);

  // The owner keeps Unlimited at the front desk.
  await page.goto("/admin/finance?tab=packages&package=p-unl");
  await page.getByTestId("package-advanced").locator("summary").click();
  const toggle = page.getByTestId("sold-online-card").getByRole("switch", { name: "Πωλείται online" });
  await expect(toggle).toHaveAttribute("aria-checked", "true");
  await toggle.click();
  await expect(page.getByTestId("sold-online-card").getByRole("status")).toContainText("Αποθηκεύτηκε");
  await expect(page.getByTestId("sold-online-hint")).toContainText("Πωλείται μόνο στην υποδοχή.");
  expect(writes.find((w) => w.path === "/api/admin/finance/packages/p-unl")?.body).toEqual({ sold_online: false });

  // ADR-681: a free package is not sold; the same switch shows it on the package page.
  await page.goto("/admin/finance?tab=packages&package=p-trial");
  await page.getByTestId("package-advanced").locator("summary").click();
  const show = page.getByTestId("sold-online-card").getByRole("switch", { name: "Φαίνεται στη Σελίδα πακέτων" });
  await expect(show).toBeVisible();
  await expect(show).toBeEnabled();
  await expect(show).toHaveAttribute("aria-checked", "false");
  await show.click();
  await expect.poll(() => writes.find((w) => w.path === "/api/admin/finance/packages/p-trial")?.body).toEqual({ sold_online: true });
});

test("ADR-553: «Ποιος βλέπει τα πακέτα συνδρομής» is one choice above the packages, for Palee and the website", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, writes);
  await page.goto("/admin/finance?tab=packages");

  const row = page.getByTestId("package-audience-row");
  await expect(row).toContainText("Ποιος βλέπει τα πακέτα συνδρομής");
  await expect(page.getByTestId("package-audience-summary")).toHaveText("Όλοι");
  await row.click();
  const sheet = page.getByTestId("package-audience-sheet");
  await sheet.getByRole("radio", { name: /Μόνο το δικό τους/ }).click();
  await expect.poll(() => writes.find((w) => w.method === "PUT" && w.path === "/api/admin/package-audience")?.body).toEqual({ audience: "own" });
});

test("ADR-596: the owner makes one package «Προτεινόμενο» on the box page", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, writes);
  await page.goto("/admin/finance?tab=packages&package=p-unl");
  await page.getByTestId("package-advanced").locator("summary").click();
  const toggle = page.getByTestId("featured-package-card").getByRole("switch", { name: "Προτεινόμενο στη σελίδα του box" });
  await expect(toggle).toHaveAttribute("aria-checked", "false");
  await toggle.click();
  await expect(toggle).toHaveAttribute("aria-checked", "true");
  expect(writes.find((w) => w.path === "/api/admin/package-audience/featured")?.body).toEqual({ package_id: "p-unl" });
});

test("mockup 1A: a package's eye in the list opens its «Ποιος το βλέπει», like the box row", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, writes);
  await page.goto("/admin/finance?tab=packages");

  const eye = page.getByTestId("package-row").filter({ hasText: /Unlimited/ }).getByTestId("package-audience-badge");
  await expect(eye).toBeVisible();
  await expect(eye).toBeEnabled();
  await eye.click();
  const sheet = page.getByTestId("package-audience-package-sheet");
  await expect(sheet).toContainText("Ποιος βλέπει το «Unlimited»");
  // The eye opens only the sheet, not the package.
  await expect(page).not.toHaveURL(/package=p-unl/);
  const nobody = sheet.getByRole("radio", { name: "Κανείς" });
  await expect(nobody).toBeVisible();
  await nobody.click();
  await expect.poll(() => writes.find((w) => w.path === "/api/admin/package-audience/packages/p-unl")?.body).toEqual({ audience: "none" });
});

test("mockup 1A + 2A: «Διαθέσιμο» and «Ποιος το βλέπει» sit at the top of the package; withdrawing asks first, bringing back is immediate", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, writes);
  await page.goto("/admin/finance?tab=packages&package=p-w3");

  const top = page.getByTestId("package-top-controls");
  await expect(top.getByTestId("package-audience-row-summary")).toHaveText("Όπως το box · Όλοι");
  const available = top.getByRole("switch", { name: "Διαθέσιμο" });
  await expect(available).toBeVisible();
  await expect(available).toHaveAttribute("aria-checked", "true");

  // «Ποιος το βλέπει» is no longer in the advanced settings.
  await page.getByTestId("package-advanced").locator("summary").click();
  await expect(page.getByTestId("package-advanced").getByTestId("package-audience-card")).toHaveCount(0);

  await available.click();
  const dialog = page.getByTestId("package-retire-dialog");
  await expect(dialog).toContainText("Απόσυρση του «3 φορές την εβδομάδα»;");
  const confirm = dialog.getByTestId("package-retire-confirm");
  await expect(confirm).toBeEnabled();
  await confirm.click();
  await expect.poll(() => writes.find((w) => w.path === "/api/admin/finance/packages/p-w3/retire")?.body).toEqual({ replacement_package_by_role: {} });

  const retired = top.getByRole("switch", { name: "Αποσυρμένο" });
  await expect(retired).toHaveAttribute("aria-checked", "false");
  await expect(top.getByTestId("package-audience-row-summary")).toHaveText("Αποσυρμένο: δεν το βλέπει κανείς");

  await retired.click();
  await expect.poll(() => writes.find((w) => w.method === "PATCH" && w.path === "/api/admin/finance/packages/p-w3")?.body).toEqual({ active: true });
  await expect(top.getByRole("switch", { name: "Διαθέσιμο" })).toHaveAttribute("aria-checked", "true");
});
