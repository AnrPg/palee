import { expect, test, type Page } from "./support/test";

// ADR-462 (mockup 2026-11-04 tab 4, option A): every staff «Στατιστικά» page
// has the period bar and «Φίλτρα», keeps them in the URL, shows each metric
// key as a widget with its own «?», and never scrolls sideways on a phone.
// The API is stubbed; unlisted routes answer `{}`.

const user = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner-1@example.com",
  email_verified: true,
  completed_tours: ["admin-dashboard"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

function tokenFor() {
  const payload = Buffer.from(JSON.stringify({ sub: user.id, role: user.role, exp: Math.floor(Date.now() / 1000) + 3600 })).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const kpi = (key: string, unit: string, value: number | null, extra: Record<string, unknown> = {}) => ({
  key,
  unit,
  kind: "flow",
  value,
  previous: value === null ? null : value - 1,
  delta: value === null ? null : 1,
  since: null,
  suppressed: false,
  previous_suppressed: false,
  rows: [],
  previous_rows: [],
  ...extra,
});

const summary = {
  kpis: {
    "training.class_fill_rate": kpi("training.class_fill_rate", "percent", 72.5),
    "training.no_show_rate": kpi("training.no_show_rate", "percent", 8),
    "training.late_cancellations": kpi("training.late_cancellations", "count", 3, { since: "2026-11-04T08:00:00Z" }),
    "training.visits_per_member_week": kpi("training.visits_per_member_week", "ratio", null, { suppressed: true }),
    "training.attendance_by_hour": kpi("training.attendance_by_hour", "rows", 9, { kind: "breakdown", rows: [{ key: 18, count: 9, people: 7 }] }),
  },
  execution: { started: 0, completed: 0 },
};

async function stubApi(page: Page, requests: string[]) {
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "owner",
          roles: ["owner"],
          capabilities: { view_finance_reports: true, reset_analytics: true },
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/admin/analytics/summary?**", (route) => {
    requests.push(new URL(route.request().url()).search);
    return route.fulfill(json(summary));
  });
  await page.route("**/api/org/*/admin/finance/summary**", (route) => {
    requests.push(new URL(route.request().url()).search);
    return route.fulfill(json({ totals: {}, kpis: { "finance.mrr": kpi("finance.mrr", "cents", 1_250_000) } }));
  });
  await page.route("**/api/org/*/admin/finance/queues?**", (route) => route.fulfill(json({ queues: {} })));
}

test.describe("staff analytics filters and widgets", () => {
  test("period and filters live in the URL and reach the API", async ({ page, context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "en", url: baseURL! }]);
    const requests: string[] = [];
    await stubApi(page, requests);
    await page.goto("/org/kypseli/admin/metrics/training");

    await expect(page.getByTestId("analytics-filter-bar")).toBeVisible();
    await expect(page.getByText("compared with the previous 30 days")).toBeVisible();
    await expect(page.getByTestId("kpi-training.no_show_rate")).toContainText("8%");
    await expect(page.getByTestId("kpi-training.visits_per_member_week")).toContainText("—");
    await expect(page.getByTestId("kpi-training.late_cancellations").getByTestId("metric-since")).toBeVisible();

    await page.getByRole("button", { name: "90 days" }).click();
    await expect(page).toHaveURL(/period=90/);
    await expect.poll(() => requests.some((search) => search.includes("days=90"))).toBe(true);

    await page.getByTestId("analytics-filters-button").click();
    const sheet = page.getByTestId("analytics-filter-sheet");
    await sheet.getByRole("button", { name: "Evening" }).click();
    await sheet.getByRole("button", { name: "Done" }).click();
    await expect(page).toHaveURL(/time_of_day=evening/);
    await expect(page.getByRole("button", { name: "Remove Time: Evening" })).toBeVisible();
  });

  test("each widget has its own infobox; the reset sits in its footer", async ({ page, context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "en", url: baseURL! }]);
    await stubApi(page, []);
    await page.goto("/org/kypseli/admin/metrics/training");

    const keys = await page.locator("[data-help-key]").evaluateAll((nodes) => nodes.map((node) => (node as HTMLElement).dataset.helpKey));
    expect(new Set(keys).size).toBe(keys.length);

    await page.getByRole("button", { name: "About: No-shows" }).click();
    await expect(page.getByRole("dialog", { name: "About: No-shows" }).getByRole("button", { name: "Reset from today" })).toBeVisible();
  });

  test("no horizontal page scroll on a phone", async ({ page, context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "el", url: baseURL! }]);
    await page.setViewportSize({ width: 360, height: 780 });
    await stubApi(page, []);
    for (const path of ["/org/kypseli/admin/metrics/training", "/org/kypseli/admin/metrics/finance"]) {
      await page.goto(path);
      await expect(page.getByTestId("analytics-filter-bar")).toBeVisible();
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      expect(overflow).toBeLessThanOrEqual(0);
    }
  });
});
