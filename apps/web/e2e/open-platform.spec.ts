import { expect, test, type Page, type Route } from "./support/test";

// W10 (ADR-378..381, screens decided 2026-11-02): Settings › Connections
// (the API key guide, webhooks with their own page and delivery log, the
// email list with its unsubscribe address), the doors of a branch, the
// door's answer after the member's scan, and the access log. The API is
// stubbed; every route not listed answers an empty object.

type Write = { path: string; method: string; body: unknown };

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");
const ago = (minutes: number) => new Date(Date.now() - minutes * 60_000).toISOString();

function persona(role: "owner" | "member") {
  const user = {
    id: role === "owner" ? "owner-1" : "member-1",
    nickname: role === "owner" ? "Apostolos" : "Maria",
    role: role === "owner" ? "admin" : "member",
    email: `${role}@example.com`,
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role, settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const membership = {
    role,
    roles: [role],
    capabilities: role === "owner" ? { manage_settings: true, manage_locations: true, check_in: true } : {},
    organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", provider_kind: "gym", activation: "active" },
    settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
  };
  return { user, membership, token: `stub.${payload}.signature` };
}

const catalog = {
  scopes: [
    { scope: "members:read", label: { en: "Read members", el: "Ανάγνωση μελών" } },
    { scope: "classes:read", label: { en: "Read classes", el: "Ανάγνωση τμημάτων" } },
    { scope: "bookings:read", label: { en: "Read bookings", el: "Ανάγνωση κρατήσεων" } },
    { scope: "webhooks:write", label: { en: "Subscribe", el: "Συνδρομή" } },
  ],
  events: [
    { type: "booking.created", label: { en: "New booking", el: "Νέα κράτηση" } },
    { type: "payment.recorded", label: { en: "Payment", el: "Πληρωμή" } },
  ],
  audience_providers: ["mailchimp", "brevo"],
};

const failingHook = {
  id: "hook-1",
  url: "https://hooks.zapier.com/hooks/catch/1/8812",
  events: ["booking.created"],
  status: "active",
  source: "staff",
  consecutive_failures: 3,
  last_success_at: ago(120),
  last_failure_at: ago(5),
  created_at: ago(600),
};

const failedDelivery = {
  id: "del-1",
  endpoint_id: "hook-1",
  event_id: "evt-1",
  event_type: "booking.created",
  status: "failed",
  attempts: 8,
  last_status_code: 500,
  next_attempt_at: null,
  inserted_at: ago(5),
  payload: { type: "booking.created", data: { booking_id: "b-1" } },
  attempts_log: [{ attempt: 8, outcome: "failed", status_code: 500, started_at: ago(5), duration_ms: 120 }],
};

const door = {
  id: "door-1",
  location_id: "loc-1",
  name: "Main entrance",
  provider: "shelly",
  status: "active",
  credentials_saved: true,
  rules: { who: "booked_or_covered", staff_always: true, window_before_minutes: 30, window_after_minutes: 15, unlock_seconds: 5, hours: [] },
};

const location = {
  id: "loc-1",
  organization_id: "org-1",
  name: "Box Kypseli",
  address: null,
  latitude: null,
  longitude: null,
  neighbourhood: null,
  city: null,
  country_code: null,
  opening_hours: [],
  accessibility: [],
  archived_at: null,
};

/** The whole API for one persona: W10's routes answer from `state`, the rest `{}`. */
async function stub(page: Page, as: "owner" | "member", writes: Write[], overrides: Record<string, (route: Route, body: unknown) => unknown> = {}) {
  const { user, membership, token } = persona(as);
  let connection: Record<string, unknown> | null = null;
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    const body = method === "GET" || method === "DELETE" ? null : route.request().postDataJSON();
    if (method !== "GET") writes.push({ path, method, body });
    const override = overrides[`${method} ${path}`];
    if (override) return override(route, body);
    if (path === "/api/auth/refresh") return json(route, { access_token: token, refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, user);
    if (path === "/api/memberships") return json(route, [membership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/admin/settings") return json(route, { gamification: {}, finance: {}, scheduling: {} });
    if (path === "/api/admin/integrations/catalog") return json(route, catalog);
    if (path === "/api/admin/integrations/api-keys") {
      if (method === "POST") {
        const { name, scopes } = body as { name: string; scopes: string[] };
        return json(route, { key: { id: "key-1", name, scopes, prefix: "k3m9", masked: "palee_live_k3m9_…", status: "active", created_at: ago(0) }, token: "palee_live_k3m9_secretsecret" }, 201);
      }
      return json(route, { keys: [] });
    }
    if (path === "/api/admin/integrations/webhooks") return json(route, { webhooks: [failingHook] });
    if (path === "/api/admin/integrations/webhooks/hook-1/deliveries") return json(route, { deliveries: [failedDelivery], total: 1 });
    if (path === "/api/admin/integrations/deliveries/del-1") return json(route, { delivery: failedDelivery });
    if (path === "/api/admin/integrations/deliveries/del-1/replay")
      return json(route, { delivery: { ...failedDelivery, id: "del-2", status: "succeeded", attempts: 1, replay_of_id: "del-1" } });
    if (path === "/api/admin/integrations/email-list") {
      if (method === "PUT") {
        const put = body as { provider: string; list_id: string };
        connection = { provider: put.provider, list_id: put.list_id, status: "active", key_saved: true, unsubscribe_hook: false, last_synced_at: null };
      }
      return json(route, { connection });
    }
    if (path === "/api/admin/integrations/email-list/unsubscribe-url")
      return json(route, { url: "https://palee.app/api/integrations/email-list/conn-1/unsubscribe?token=tok" });
    if (path === "/api/admin/locations") return json(route, { locations: [location] });
    if (path === "/api/admin/locations/loc-1") return json(route, { location });
    if (path === "/api/admin/doors/catalog") return json(route, { providers: ["shelly", "kisi"], whos: ["booked_or_covered", "members", "staff_only"] });
    if (path === "/api/admin/doors") return json(route, { doors: [door] });
    if (path === "/api/admin/doors/door-1/unlock") return json(route, { opened: true });
    if (path === "/api/admin/doors/door-1") return json(route, { ok: true });
    if (path === "/api/admin/access-events")
      return json(route, {
        total: 3,
        events: [
          { id: "ev-1", kind: "granted", method: "qr", reason: "booked_class", person_name: "Maria P.", door_name: "Main entrance", occurred_at: ago(3) },
          { id: "ev-2", kind: "denied", method: "qr", reason: "no_booking_in_window", person_name: "Nikos K.", door_name: "Main entrance", occurred_at: ago(9) },
          { id: "ev-3", kind: "staff_unlock", method: "staff", actor_name: "Apostolos", door_name: "Main entrance", occurred_at: ago(15) },
        ],
      });
    return json(route, {});
  });
}

const posted = (writes: Write[], method: string, path: string) => writes.find((write) => write.method === method && write.path === path)?.body;

test.describe("Settings › Connections", () => {
  test("API keys: a guide asks what for, suggests the fewest rights, and shows the key once", async ({ page }) => {
    const writes: Write[] = [];
    await stub(page, "owner", writes);
    await page.goto("/admin/settings?connections=keys#connections");

    const section = page.locator("#connections");
    await section.getByTestId("api-key-new").click();
    const guide = page.getByTestId("api-key-guide");
    await expect(guide).toContainText("Step 1 of 3");
    await guide.getByRole("radio", { name: /Zapier or Make/ }).click();
    await guide.getByTestId("api-key-continue").click();
    await expect(guide).toContainText("Suggested for «Zapier or Make»");
    await guide.getByTestId("api-key-create").click();

    await expect(guide.getByTestId("api-key-token")).toContainText("palee_live_k3m9_secretsecret");
    await expect(guide).toContainText("You will not see it again.");
    await expect(guide).toContainText("In Zapier");
    await expect
      .poll(() => posted(writes, "POST", "/api/admin/integrations/api-keys"))
      .toMatchObject({ name: "Zapier", scopes: ["bookings:read", "classes:read", "members:read", "webhooks:write"] });
  });

  test("webhooks: the list says which one fails; its page has the log, the attempts and «Send again»", async ({ page }) => {
    const writes: Write[] = [];
    await stub(page, "owner", writes);
    await page.goto("/admin/settings?connections=webhooks#connections");

    const row = page.locator("#connections").getByTestId("webhook-row");
    await expect(row).toContainText("hooks.zapier.com/…/8812");
    await expect(row).toContainText("Failing");
    await row.click();

    await expect(page).toHaveURL(/\/admin\/settings\/webhooks\/hook-1/);
    await expect(page.getByTestId("webhook-head")).toContainText("Failing");
    const log = page.getByTestId("delivery-log");
    await log.getByRole("tab", { name: "Failed" }).click();
    await log.getByTestId("delivery-row").first().click();

    const detail = page.getByTestId("delivery-detail");
    await expect(detail).toContainText("booking.created");
    await expect(detail).toContainText("500");
    await detail.getByTestId("delivery-replay").click();
    await expect(page.getByText("Sent again as a new delivery.")).toBeVisible();
    expect(writes.some((write) => write.path === "/api/admin/integrations/deliveries/del-1/replay")).toBe(true);
  });

  test("email list: errors stay in the form; once connected, the unsubscribe address waits under «Advanced»", async ({ page }) => {
    const writes: Write[] = [];
    await stub(page, "owner", writes);
    await page.goto("/admin/settings?connections=list#connections");

    const card = page.locator("#connections").getByTestId("email-list");
    await expect(card).toContainText("Only members who said yes are sent");
    await card.getByTestId("email-list-connect").click();
    await expect(card).toContainText("Enter the service's API key.");
    await expect(card).toContainText("Enter the list's id.");
    expect(writes.some((write) => write.path === "/api/admin/integrations/email-list")).toBe(false);

    await card.getByLabel("API key").fill("0123456789abcdef-us21");
    await card.getByLabel("List").fill("abc123");
    await card.getByTestId("email-list-connect").click();
    await expect(card).toContainText("Email list · Mailchimp");
    await expect.poll(() => posted(writes, "PUT", "/api/admin/integrations/email-list")).toMatchObject({ provider: "mailchimp", list_id: "abc123" });

    const advanced = card.getByTestId("email-list-advanced");
    await expect(advanced.getByTestId("email-list-unsubscribe")).toBeHidden();
    await advanced.getByRole("button", { name: /Advanced/ }).click();
    const hook = advanced.getByTestId("email-list-unsubscribe");
    await expect(hook).toContainText("Not set up");
    await hook.getByTestId("email-list-unsubscribe-make").click();
    await expect(hook.getByTestId("email-list-unsubscribe-url")).toContainText("/api/integrations/email-list/conn-1/unsubscribe?token=tok");
    await expect(hook).toContainText("tick only “Unsubscribes”");
    await expect(hook).toContainText("Connected");
  });
});

test.describe("Doors", () => {
  test("the branch lists its doors: open from the desk, entry rules, and removal asks first", async ({ page }) => {
    const writes: Write[] = [];
    await stub(page, "owner", writes);
    await page.goto("/admin/settings/locations/loc-1");

    const doors = page.getByTestId("location-doors");
    const row = doors.getByTestId("door-row");
    await expect(row).toContainText("Main entrance");
    await expect(row).toContainText("Shelly relay · With a booking or open gym");
    await expect(row).toContainText("Connected");

    await row.getByTestId("door-unlock").click();
    await expect(doors.getByTestId("door-opened")).toContainText("«Main entrance» opened.");

    await row.getByRole("button", { name: "Entry rules: With a booking or open gym ›" }).click();
    const rules = page.getByTestId("door-rules");
    await rules.getByRole("radio", { name: /All active members/ }).click();
    await rules.getByTestId("door-rules-save").click();
    await expect.poll(() => posted(writes, "PATCH", "/api/admin/doors/door-1")).toMatchObject({ rules: { who: "members" } });

    await row.getByRole("button", { name: "More" }).click();
    await page.getByRole("menuitem", { name: "Remove" }).click();
    await expect(page.getByRole("dialog", { name: "Remove “Main entrance”?" })).toBeVisible();
    expect(writes.some((write) => write.method === "DELETE")).toBe(false);
    await page.getByTestId("door-remove-confirm").click();
    await expect.poll(() => writes.some((write) => write.method === "DELETE" && write.path === "/api/admin/doors/door-1")).toBe(true);

    await expect(doors.getByRole("link", { name: "Access log ›" })).toHaveAttribute("href", /\/admin\/check-in\/access-log/);
  });

  test("the access log names who and which door, and filters refusals", async ({ page }) => {
    await stub(page, "owner", []);
    await page.goto("/admin/check-in/access-log");

    const log = page.getByTestId("access-log");
    await expect(log.getByTestId("access-row")).toHaveCount(3);
    await expect(log).toContainText("Maria P. · entered");
    await expect(log).toContainText("Apostolos · opened from the desk");
    await log.getByRole("radio", { name: "Refusals and faults" }).click();
    await expect(log.getByTestId("access-row")).toHaveCount(1);
    await expect(log.getByTestId("access-row")).toContainText("Nikos K. · not let in");
    await expect(log.getByTestId("access-row")).toContainText("No booking now · Main entrance");
  });

  test("the door's QR checks in and opens the door: one answer", async ({ page }) => {
    const writes: Write[] = [];
    await stub(page, "member", writes, {
      "POST /api/check-in/scan": (route) =>
        json(route, {
          outcome: "checked_in",
          box: { organization_id: "org-1", slug: "kypseli", name: "Box Kypseli", logo_url: null, primary_color: null },
          location: { id: "loc-1", name: "Kypseli" },
          membership: "member",
          check_in: { id: "ci-1", at: ago(0), kind: "class", method: "door_qr", booking: null },
          package: null,
          undo_token: "undo-1",
          undo_until: new Date(Date.now() + 60_000).toISOString(),
        }),
      "POST /api/access/open": (route) => json(route, { opened: true, reason: "booked_class", seconds: 5, door: { id: "door-1", name: "Main entrance" } }),
    });
    await page.goto("/c/loc-1/D1doorcode");

    await expect(page.getByTestId("door-answer-opened")).toContainText("The door opened");
    await expect(page.getByTestId("door-answer-opened")).toContainText("Main entrance · for 5″");
    await expect(page.getByTestId("scan-checked-in")).toBeVisible();
    expect(posted(writes, "POST", "/api/access/open")).toEqual({ location_id: "loc-1", code: "D1doorcode" });
  });

  test("the printed poster checks in but never asks the door", async ({ page }) => {
    const writes: Write[] = [];
    await stub(page, "member", writes, {
      "POST /api/check-in/scan": (route) =>
        json(route, {
          outcome: "checked_in",
          box: { organization_id: "org-1", slug: "kypseli", name: "Box Kypseli", logo_url: null, primary_color: null },
          location: { id: "loc-1", name: "Kypseli" },
          membership: "member",
          check_in: { id: "ci-1", at: ago(0), kind: "class", method: "poster", booking: null },
          package: null,
          undo_token: "undo-1",
          undo_until: new Date(Date.now() + 60_000).toISOString(),
        }),
    });
    await page.goto("/c/loc-1/p/P0STERcode");

    await expect(page.getByTestId("scan-checked-in")).toBeVisible();
    await expect(page.getByTestId("door-answer-opened")).toBeHidden();
    expect(writes.some((write) => write.path === "/api/access/open")).toBe(false);
  });
});
