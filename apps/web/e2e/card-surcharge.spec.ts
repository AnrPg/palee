import { expect, test, type Page, type Route } from "./support/test";

// Card surcharge (ADR-340, W1 mockup): s1 B the 3-step guide in
// Ρυθμίσεις › Πληρωμές, s3 A «Τι κάρτα έδωσε;» at «Κάρτα στο POS» when
// recording a payment, and s2 A the surcharge as a line in the member's
// total. The API is stubbed; anything not stubbed answers `{}`.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

type Write = { method: string; path: string; body: unknown };

function tokenFor(sub: string, role: string) {
  const payload = Buffer.from(
    JSON.stringify({ sub, role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const OWNER = {
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

const OWNER_MEMBERSHIP = {
  role: "owner",
  roles: ["owner"],
  capabilities: { manage_settings: true, manage_billing: true, take_payments: "all", view_finance_reports: true, manage_memberships: "all" },
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", timezone: "Europe/Athens", timezone_confirmed: true },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

const LAW = { rule: "eea_non_consumer", regime: "psd2", cap_bps: null, at_cost: true, region_required: false, sources: ["PSD2 art. 62"] };
const OFF = { percent_bps: 0, fixed_cents: 0, channels: [], at_cost_confirmed: false, enabled: false, region_code: null };

async function stubOwner(page: Page, writes: Write[], extra?: (path: string, method: string, body: unknown, route: Route) => Promise<void> | null) {
  let settings: Record<string, unknown> = { ...OFF };
  let saved = false;
  const status = () => ({ allowed: true, country_code: "GR", law: LAW, saved, settings, updated_at: null });
  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    const body = method === "GET" || method === "DELETE" ? null : route.request().postDataJSON();
    if (method !== "GET") writes.push({ method, path, body });
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(OWNER.id, "admin"), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, OWNER);
    if (path === "/api/memberships") return json(route, [OWNER_MEMBERSHIP]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/join-link") return json(route, { member: { enabled: false }, athlete: { enabled: false, key: null } });
    if (path === "/api/admin/payments/surcharge" && method === "PUT") {
      settings = { ...settings, ...(body as Record<string, unknown>) };
      saved = true;
      return json(route, status());
    }
    if (path === "/api/admin/payments/surcharge") return json(route, status());
    if (extra) {
      const handled = extra(path, method, body, route);
      if (handled) return handled;
    }
    return json(route, {});
  });
}

test("the owner turns the card surcharge on in three steps, POS off by default", async ({ page }) => {
  const writes: Write[] = [];
  await stubOwner(page, writes);
  await page.goto("/admin/settings?tab=payments");

  const card = page.getByTestId("card-surcharge");
  await expect(card.getByTestId("card-surcharge-summary")).toHaveText("Κλειστή. Το box δεν προσθέτει τίποτα στις πληρωμές με κάρτα.");
  await card.getByRole("button", { name: "Ρύθμιση" }).click();

  const guide = page.getByTestId("card-surcharge-guide");
  // Step 1: the law of the box's country in one sentence.
  await expect(guide.getByTestId("card-surcharge-law")).toContainText("Μόνο επαγγελματικές κάρτες και κάρτες εκτός ΕΟΧ");
  await guide.getByTestId("card-surcharge-next").click();

  // Step 2: the percent, and the at-cost confirmation the law asks for.
  const percent = guide.getByLabel("Ποσοστό");
  await percent.fill("");
  await guide.getByTestId("card-surcharge-next").click();
  await expect(percent).toHaveAttribute("aria-invalid", "true");
  await percent.fill("1,5");
  await guide.getByRole("checkbox", { name: /πραγματικό κόστος/ }).check();
  await expect(guide.getByTestId("card-surcharge-example")).toContainText("0,90");
  await guide.getByTestId("card-surcharge-next").click();

  // Step 3: where it applies; «Κάρτα στο POS» starts off.
  await expect(guide.getByTestId("card-surcharge-channel-online")).toBeChecked();
  await expect(guide.getByTestId("card-surcharge-channel-desk")).not.toBeChecked();
  await guide.getByTestId("card-surcharge-channel-desk").check();
  await guide.getByTestId("card-surcharge-enable").click();

  await expect(card.getByTestId("card-surcharge-summary")).toContainText("Ισχύει");
  const put = writes.findLast((write) => write.path === "/api/admin/payments/surcharge" && write.method === "PUT");
  expect(put?.body).toMatchObject({ enabled: true, percent_bps: 150, fixed_cents: 0, channels: ["online", "terminal", "desk"], at_cost_confirmed: true });
});

const MEMBER_ID = "a11ce000-0000-4000-8000-000000000001";

test("at «Κάρτα στο POS» the desk asks what card it was and shows the amount to type", async ({ page }) => {
  const writes: Write[] = [];
  const quotes: unknown[] = [];
  const member = { id: MEMBER_ID, nickname: "Maria", identity_role: "member", user_type: "member", membership: { status: "active" }, active_package_subscription: null };
  await stubOwner(page, writes, (path, method, body, route) => {
    if (path === "/api/admin/payments/surcharge/quote") {
      quotes.push(body);
      const card = (body as { card: Record<string, unknown> | null }).card;
      const applies = card?.commercial === true;
      return json(route, {
        applies,
        rule: "eea_non_consumer",
        percent_bps: 150,
        fixed_cents: 0,
        surcharge_cents: applies ? 90 : 0,
        total_cents: applies ? 6090 : 6000,
        reason: card ? (applies ? null : "card_not_surchargeable") : "card_unknown",
      });
    }
    if (path === "/api/admin/finance/package-catalog") return json(route, { types: [], modules: [] });
    if (path === "/api/admin/finance/members") return json(route, { members: [member], meta: {} });
    if (path === "/api/admin/settings") return json(route, { finance: { document_mode: "receipt", payment_reminder_interval_days: 7 } });
    if (path === `/api/admin/finance/members/${MEMBER_ID}`) {
      return json(route, {
        membership: { status: "active" },
        package_subscriptions: [{ id: "sub-1", status: "active", package_name: "Unlimited monthly", price_cents_snapshot: 6000 }],
        invoices: [],
        payments: [],
        payment_reversals: [],
        credit_ledger_entries: [],
      });
    }
    if (path === `/api/admin/finance/members/${MEMBER_ID}/payments/receive` && method === "POST") {
      return json(route, {
        received: {
          document_type: "receipt",
          reference: "R-0009",
          issued_on: "2026-11-02",
          amount_cents: 6090,
          currency: "EUR",
          description: "Unlimited monthly",
          package_name: "Unlimited monthly",
          replayed: false,
          invoice: { id: "inv-9", status: "paid", balance_due_cents: 0 },
          payment: { id: "pay-9", payment_method: "card_manual" },
        },
      }, 201);
    }
    return null;
  });
  await page.goto("/admin/finance?tab=members");

  await page.getByRole("button", { name: "Καταγραφή πληρωμής από Maria" }).click();
  const dialog = page.getByRole("dialog").filter({ has: page.getByTestId("receive-payment-outcome") });
  await dialog.getByRole("radio", { name: "Κάρτα στο POS" }).click();

  const question = dialog.getByTestId("desk-surcharge");
  await expect(question.getByText("Τι κάρτα έδωσε;")).toBeVisible();
  await expect(question.getByTestId("desk-card-unknown")).toHaveAttribute("aria-checked", "true");
  await question.getByTestId("desk-card-business").click();
  await expect(question.getByTestId("desk-surcharge-amount")).toContainText("0,90");
  await expect(question.getByTestId("desk-surcharge-total")).toContainText("60,90");

  await dialog.getByRole("button", { name: "Καταγραφή πληρωμής", exact: true }).click();
  const receivePath = `/api/admin/finance/members/${MEMBER_ID}/payments/receive`;
  await expect.poll(() => writes.some((write) => write.path === receivePath)).toBe(true);
  const receive = writes.find((write) => write.path === receivePath);
  expect(receive?.body).toMatchObject({ payment_method: "card_manual", amount_cents: 6000, surcharge_cents: 90, card: { commercial: true } });
  expect(quotes.length).toBeGreaterThan(0);
});

const MEMBER = {
  id: "maria",
  nickname: "Maria",
  role: "member",
  email: "maria@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "el",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};

const MEMBER_MEMBERSHIP = {
  id: "m-1",
  role: "member",
  roles: ["member"],
  capabilities: {},
  home_location_id: "loc-1",
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", provider_kind: "gym", activation: "active", timezone: "UTC" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

const UNLIMITED = {
  id: "unl",
  name: "Unlimited",
  description: "Απεριόριστες επισκέψεις",
  package_type: "membership",
  billing_period: "monthly",
  base_price_cents: 7500,
  currency: "EUR",
  services: { "group_classes.included": true },
};

test("the member sees the card surcharge as a line in the total before paying", async ({ page }) => {
  await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(MEMBER.id, "member"), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, MEMBER);
    if (path === "/api/memberships") return json(route, [MEMBER_MEMBERSHIP]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/public/boxes/kypseli/packages") return json(route, { packages: [UNLIMITED], online_payments: true, provider: "viva", withdrawal_days: 14 });
    if (path === "/api/me/packages/unl/purchase-terms") {
      return json(route, {
        package: UNLIMITED,
        available: true,
        provider: "sandbox",
        withdrawal_days: 14,
        start_now_text: "Ζητώ να ξεκινήσει το πακέτο αμέσως.",
        consent_text: "Επιτρέπω χρεώσεις.",
        consent_version: "2026-10-v1",
        surcharge: { applies: true, surcharge_cents: 113, total_cents: 7613, percent_bps: 150, fixed_cents: 0, reason: null },
      });
    }
    return json(route, {});
  });

  await page.goto("/box");
  await page.getByTestId("pay-renew").click();
  const sheet = page.getByTestId("pay-sheet");
  await sheet.getByRole("button", { name: "Συνέχεια" }).click();

  const total = sheet.getByTestId("pay-surcharge");
  await expect(total).toContainText("Επιβάρυνση κάρτας");
  await expect(total.getByTestId("pay-surcharge-amount")).toContainText("1,13");
  await expect(total.getByTestId("pay-surcharge-total")).toContainText("76,13");
  await sheet.getByTestId("pay-start-now").click();
  await sheet.getByTestId("pay-auto-yes").click();
  await expect(sheet.getByTestId("pay-submit")).toHaveText(/76,13/);
});
