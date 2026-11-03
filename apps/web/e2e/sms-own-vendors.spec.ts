import { expect, test, type Page, type Route } from "./support/test";

// ADR-396: a box brings its own SMS vendor under «Advanced» at Settings ›
// Connections › Text messages (SMS): it picks the vendor, follows that
// vendor's guide, and a wrong or refused field is explained under it.
// The API is stubbed.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

function tokenFor(user: { id: string; role: string }) {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

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

const membership = {
  role: "owner",
  roles: ["owner"],
  capabilities: { manage_settings: true, message_from_box: true, view_analytics: true },
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", activation: "active" },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

const usage = { from: "", to: "", spent_cents: 0, messages: 0, by_channel: {}, currency: "EUR", account_mode: "palee", palee_charge_cents: 0 };

const providers = [
  { provider: "brevo", channels: ["sms"], account_modes: ["own", "palee"] },
  ...["twilio", "vonage", "infobip", "yuboto", "apifon"].map((provider) => ({ provider, channels: ["sms"], account_modes: ["own"] })),
];

const SID = `AC${"0a".repeat(16)}`;

function connection(overrides: Record<string, unknown> = {}) {
  return {
    provider: "brevo",
    account_mode: "palee",
    channel_order: ["sms"],
    channels: ["sms"],
    default_country: "GR",
    has_secret: false,
    has_webhook_secret: false,
    monthly_budget_cents: 2000,
    quiet_start: "21:00",
    quiet_end: "09:00",
    sms_sender: "BoxKypseli",
    status: "active",
    currency: "EUR",
    checked_at: null,
    webhook_url: "https://palee.app/api/webhooks/channels/org-1/token",
    ...overrides,
  };
}

type Write = { path: string; method: string; body: Record<string, unknown> };

async function stub(page: Page, writes: Write[]) {
  let current = connection();
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    const body = method === "GET" ? null : (route.request().postDataJSON() as Record<string, unknown>);
    if (body !== null) writes.push({ path, method, body });
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(owner), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, owner);
    if (path === "/api/memberships") return json(route, [membership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/admin/settings") return json(route, { gamification: {}, finance: {}, scheduling: {} });
    if (path === "/api/join-link") return json(route, { member: { enabled: false }, athlete: { enabled: false, key: null } });
    if (path === "/api/admin/community/groups") return json(route, { settings: { member_groups: "none" }, pending: [], groups: [] });
    if (path === "/api/admin/channels/settings") {
      if (method === "PUT" && body) {
        // The stub refuses a Twilio token that says «wrong», like a real check would.
        if (body.provider === "twilio" && body.secret === "wrong") {
          current = connection({ provider: "twilio", account_mode: "own", account_id: SID, has_secret: true, status: "invalid" });
          return json(route, { connection: current, check: { ok: false, error_code: "credentials_rejected", details: {} } });
        }
        current = connection({ provider: body.provider, account_mode: body.account_mode, account_id: body.account_id ?? null, has_secret: true });
        return json(route, { connection: current, check: { ok: true, details: {} } });
      }
      return json(route, { connection: current, providers, usage });
    }
    if (path === "/api/admin/channels/usage") return json(route, usage);
    if (path === "/api/admin/channels/templates") return json(route, { templates: [] });
    if (path === "/api/admin/channels/email") return json(route, { connection: null, dns: [] });
    return json(route, {});
  });
}

test("the box connects its own Twilio account with the guide, and a refused token is explained", async ({ page }) => {
  const writes: Write[] = [];
  await stub(page, writes);
  await page.goto("/admin/settings#connections");

  const section = page.locator("#connections");
  await section.getByRole("button", { name: /Advanced/ }).click();
  const own = section.getByTestId("sms-own-account");
  await own.getByRole("button", { name: "Use my own SMS provider" }).click();

  // Brevo first, as before; then the box picks Twilio and sees Twilio's guide and fields.
  await expect(own.getByTestId("brevo-guide")).toBeVisible();
  await own.getByLabel("SMS provider").click();
  await page.getByRole("option", { name: "Twilio" }).click();
  await expect(own.getByTestId("twilio-guide")).toContainText("console.twilio.com");

  // Errors stay in the form, under the field.
  await own.getByRole("button", { name: "Save key" }).click();
  await expect(own.getByText("Fill this in.")).toHaveCount(2);
  await own.getByLabel("Account SID").fill("AC123");
  await expect(own.getByText("The Account SID starts with AC and has 34 characters.")).toBeVisible();
  expect(writes.some((write) => write.method === "PUT")).toBe(false);

  await own.getByLabel("Account SID").fill(SID);
  await own.getByLabel("Auth Token").fill("wrong");
  await own.getByRole("button", { name: "Save key" }).click();
  await expect(own.getByText("Twilio did not accept these details.")).toBeVisible();

  await own.getByLabel("Auth Token").fill("tw-token");
  await own.getByRole("button", { name: "Save key" }).click();
  await expect
    .poll(() => writes.filter((write) => write.method === "PUT").at(-1)?.body)
    .toEqual({ provider: "twilio", account_mode: "own", account_id: SID, secret: "tw-token" });
  await expect(section.getByText("Your own Twilio account").first()).toBeVisible();
  await expect(own.getByRole("button", { name: "Back to Palee's account" })).toBeVisible();
});

test("each vendor shows its own guide and fields", async ({ page }) => {
  await stub(page, []);
  await page.goto("/admin/settings#connections");

  const section = page.locator("#connections");
  await section.getByRole("button", { name: /Advanced/ }).click();
  const own = section.getByTestId("sms-own-account");
  await own.getByRole("button", { name: "Use my own SMS provider" }).click();

  const vendors: Array<[string, string, string[]]> = [
    ["Vonage", "vonage-guide", ["API key", "API secret", "Signature secret"]],
    ["Infobip", "infobip-guide", ["Base URL", "API key"]],
    ["Yuboto", "yuboto-guide", ["OMNI API key"]],
    ["Apifon", "apifon-guide", ["API token", "Secret key"]],
  ];
  for (const [name, guide, fields] of vendors) {
    await own.getByLabel("SMS provider").click();
    await page.getByRole("option", { name }).click();
    await expect(own.getByTestId(guide).locator("li")).toHaveCount(4);
    for (const field of fields) await expect(own.getByLabel(field, { exact: true })).toBeVisible();
  }
});
