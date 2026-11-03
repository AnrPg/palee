import { expect, test, type Page, type Route } from "./support/test";

// W3 SMS channels (ADR-385): the SMS connection lives in Settings ›
// Connections, says plainly when a demo box sends nothing, and the month's
// cost sits in the «Text messages (SMS)» tab of Analytics & Marketing.
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

function membership(activation: "demo" | "active") {
  return {
    role: "owner",
    roles: ["owner"],
    capabilities: { manage_settings: true, message_from_box: true, view_analytics: true },
    organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", activation },
    settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
  };
}

const month = new Date().toISOString().slice(0, 7);

const usage = {
  from: `${month}-01T00:00:00Z`,
  to: `${month}-28T00:00:00Z`,
  spent_cents: 1240,
  messages: 186,
  segments: 204,
  by_channel: { sms: { cents: 1240, count: 186 } },
  by_source: { automation: { cents: 800, count: 120 }, staff: { cents: 240, count: 36 }, system: { cents: 200, count: 30 } },
  by_status: { delivered: 180, failed: 6 },
  cap_cents: 2000,
  currency: "EUR",
  account_mode: "palee",
  palee_charge_cents: 1240,
};

function connection(channels: string[]) {
  return {
    provider: "brevo",
    account_mode: "palee",
    channel_order: ["sms"],
    channels,
    default_country: "GR",
    has_secret: false,
    monthly_budget_cents: 2000,
    quiet_start: "21:00",
    quiet_end: "09:00",
    sms_sender: "BoxKypseli",
    status: "active",
    currency: "EUR",
    checked_at: null,
  };
}

async function stub(page: Page, activation: "demo" | "active", writes: Array<{ path: string; method: string; body: unknown }>) {
  let current: ReturnType<typeof connection> | null = null;
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    const body = method === "GET" ? null : route.request().postDataJSON();
    if (body !== null) writes.push({ path, method, body });
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(owner), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, owner);
    if (path === "/api/memberships") return json(route, [membership(activation)]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/admin/settings") return json(route, { gamification: {}, finance: {}, scheduling: {} });
    if (path === "/api/join-link") return json(route, { member: { enabled: false }, athlete: { enabled: false, key: null } });
    if (path === "/api/admin/community/groups") return json(route, { settings: { member_groups: "none" }, pending: [], groups: [] });
    if (path === "/api/admin/channels/settings") {
      if (method === "PUT") {
        current = connection((body as { channels?: string[] }).channels ?? current?.channels ?? []);
        return json(route, { connection: current, check: { ok: true, details: {} } });
      }
      return json(route, { connection: current, providers: [{ provider: "brevo", channels: ["sms"], account_modes: ["palee", "own"] }], usage });
    }
    if (path === "/api/admin/channels/usage") return json(route, usage);
    if (path === "/api/admin/channels/templates") return json(route, { templates: [] });
    if (path === "/api/admin/channels/email") return json(route, { connection: null, dns: [] });
    if (path === "/api/admin/channels/messages") {
      return json(route, {
        total: 1,
        messages: [
          {
            id: "m1",
            channel: "sms",
            purpose: "service",
            status: "delivered",
            source: "staff",
            to: "+30 •••••••678",
            body: "Box Kypseli: WOD 18:00 is cancelled.",
            segments: 1,
            cost_cents: 6,
            currency: "EUR",
            inserted_at: new Date().toISOString(),
          },
        ],
      });
    }
    return json(route, {});
  });
}

test("a demo box is told plainly that no SMS leave, and can still switch SMS on", async ({ page }) => {
  const writes: Array<{ path: string; method: string; body: unknown }> = [];
  await stub(page, "demo", writes);
  await page.goto("/admin/settings#connections");

  const section = page.locator("#connections");
  await section.getByRole("button", { name: /Connections/ }).first().click();
  await expect(section.getByTestId("sms-demo-notice")).toContainText("no SMS leave until it is activated");

  await section.getByRole("switch", { name: "Text messages (SMS)" }).click();
  await expect
    .poll(() => writes.find((write) => write.path === "/api/admin/channels/settings" && write.method === "PUT")?.body)
    .toMatchObject({ channels: ["sms"], account_mode: "palee" });
  await expect(section.getByTestId("sms-status")).toHaveText("Connected");
  await expect(section.getByLabel("Sender")).toHaveValue("BoxKypseli");

  // Own Brevo key and own SMTP stay under «Advanced», each with its guide.
  await expect(section.getByTestId("brevo-guide")).toBeHidden();
});

test("the month's SMS cost has its own tab with the split by source", async ({ page }) => {
  await stub(page, "active", []);
  await page.goto("/admin/metrics?tab=sms");

  const cost = page.getByTestId("sms-cost");
  await expect(cost).toContainText("€12.40");
  await expect(cost).toContainText("of a €20.00 limit");
  await expect(cost).toContainText("Automations");
  await expect(cost).toContainText("Staff");
  await expect(cost).toContainText("At the limit SMS stop; the app goes on.");
  await expect(cost).toContainText("Delivered");
});
