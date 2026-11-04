import { expect, test, type Page } from "./support/test";

// Staff home › «Θέλουν προσοχή»: each alert is one ICU plural message, so the
// count is spaced from its text and the noun agrees with it in every locale
// (it used to read "1συνδρομές λήγουν μέσα σε 30 ημέρες"). The API is stubbed.

const user = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner-1@example.com",
  email_verified: true,
  completed_tours: ["admin-dashboard"],
  preferred_locale: "el",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

function tokenFor() {
  const payload = Buffer.from(JSON.stringify({ sub: user.id, role: user.role, exp: Math.floor(Date.now() / 1000) + 3600 })).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const rows = (count: number) => Array.from({ length: count }, (_, index) => ({ id: `row-${index}` }));

async function stubApi(page: Page, locale: string, counts: { expiring: number; overdue: number; pending: number; notReported?: number }) {
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json({ ...user, preferred_locale: locale })));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "owner",
          roles: ["owner"],
          capabilities: { view_finance_reports: true },
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/admin/onboarding", (route) =>
    route.fulfill(json({ audience: "gym", steps: [], completed_count: 0, total: 0, finished: true, dismissed: true, tour_completed: true })),
  );
  await page.route("**/admin/finance/summary**", (route) => route.fulfill(json({ totals: { expiring_memberships: counts.expiring } })));
  await page.route("**/admin/finance/queues**", (route) =>
    route.fulfill(json({ queues: { overdue_invoices: rows(counts.overdue), pending_payments: rows(counts.pending), pending_referral_rewards: [] } })),
  );
  // ADR-530: documents the tax authority refused or that ran out of attempts.
  await page.route("**/admin/fiscal/transmissions**", (route) =>
    route.fulfill(json({ transmissions: [], total: 0, counts: { accepted: 9, rejected: counts.notReported ?? 0, failed: 0 } })),
  );
}

test.describe("staff home attention counts", () => {
  test("Greek: one is singular, more are plural, always with a space", async ({ page, context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "el", url: baseURL! }]);
    await stubApi(page, "el", { expiring: 1, overdue: 1, pending: 3, notReported: 2 });
    await page.goto("/org/kypseli/admin");

    await expect(page.getByRole("link", { name: "1 συνδρομή λήγει μέσα σε 30 ημέρες" })).toBeVisible();
    await expect(page.getByRole("link", { name: "1 ληξιπρόθεσμο τιμολόγιο" })).toBeVisible();
    await expect(page.getByRole("link", { name: "3 εκκρεμείς πληρωμές" })).toBeVisible();
    await expect(page.getByRole("link", { name: "2 παραστατικά δεν έφτασαν στην ΑΑΔΕ" })).toHaveAttribute(
      "href",
      "/org/kypseli/admin/finance?tab=documents",
    );
  });

  test("English plural forms", async ({ page, context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "en", url: baseURL! }]);
    await stubApi(page, "en", { expiring: 2, overdue: 1, pending: 0 });
    await page.goto("/org/kypseli/admin");

    await expect(page.getByRole("link", { name: "2 memberships expire within 30 days" })).toBeVisible();
    await expect(page.getByRole("link", { name: "1 overdue invoice" })).toBeVisible();
    await expect(page.getByText("pending payment")).toHaveCount(0);
  });

  // Beta box 2026-11-02: tapping «1 συνδρομή λήγει…» seemed to do nothing (it
  // opened the finance page on «Μέλη box») and the overdue alert had no date.
  test("each alert names its date and opens the list it counted, already picked", async ({ page, context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "en", url: baseURL! }]);
    await stubApi(page, "en", { expiring: 1, overdue: 1, pending: 0 });
    await page.route("**/admin/finance/queues**", (route) =>
      route.fulfill(
        json({
          queues: {
            overdue_invoices: [{ id: "inv-1", due_date: "2026-10-28" }],
            open_charges: [{ id: "m-1", user_id: "u-1", user_label: "tolaras", balance_due_cents: 5000, oldest_due_on: "2026-10-28", state: "overdue" }],
            expiring_memberships: [{ id: "s-1", user_id: "u-1", user_label: "tolaras", expires_on: "2026-11-28" }],
            pending_payments: [],
            pending_referral_rewards: [],
          },
        }),
      ),
    );
    await page.route("**/admin/finance/summary**", (route) =>
      route.fulfill(json({ totals: { expiring_memberships: 1, overdue_invoice_balance_cents: 5000 } })),
    );
    await page.route("**/admin/finance/package-catalog", (route) => route.fulfill(json({ types: [], modules: [] })));
    await page.route("**/admin/finance/members**", (route) => route.fulfill(json({ members: [], meta: {} })));
    await page.goto("/org/kypseli/admin");

    const expiring = page.getByRole("link", { name: /1 membership expires within 30 days/ });
    await expect(expiring).toContainText("Expires Nov 28, 2026");
    await expect(expiring).toHaveAttribute("href", "/org/kypseli/admin/finance?tab=queues&queue=expiring");
    const overdue = page.getByRole("link", { name: /1 overdue invoice/ });
    await expect(overdue).toContainText("since Oct 28, 2026");
    await expect(overdue).toHaveAttribute("href", "/org/kypseli/admin/finance?tab=queues&queue=debts");

    await expiring.click();
    await expect(page).toHaveURL(/\/org\/kypseli\/admin\/finance\?tab=queues&queue=expiring$/);
    await expect(page.locator('[data-queue="expiring"]')).toHaveAttribute("aria-pressed", "true");
    await expect(page.getByText("Expires Nov 28, 2026")).toBeVisible();
    await expect(page.getByTestId("oldest-overdue")).toContainText("since Oct 28, 2026");

    // The page's own attention chip switches the list in place.
    await page.getByRole("link", { name: /Overdue invoices: 1/ }).click();
    await expect(page.locator('[data-queue="debts"]')).toHaveAttribute("aria-pressed", "true");
    await expect(page.getByText("since Oct 28, 2026").last()).toBeVisible();
  });
});
