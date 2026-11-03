import { createServer, type Server } from "node:http";

import { expect, test, type Page, type Route } from "./support/test";

import { stubApiPort } from "../playwright.config";

// W2 leads and retention (ADR-344/345/346/347/384): the staff «Ενδιαφερόμενοι»
// kanban with its side panel, «Μέλη σε κίνδυνο» with «Επικοινώνησα», the
// automations list as a tab of Analytics & Marketing, and the visitor
// «Ενδιαφέρομαι» card on a public box page. The API is stubbed; the public
// box page's server read goes to a stub API on `stubApiPort`.

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

const daysAgo = (days: number) => new Date(Date.now() - days * 86_400_000).toISOString();

const consent = { contact_at: daysAgo(2), marketing_at: null, marketing_opted_out_at: null, text_version: "2027-05" };

function lead(id: string, name: string, stage: "new" | "trial" | "offer", extra: Record<string, unknown> = {}) {
  return {
    id,
    name,
    stage,
    source: "website_form",
    email: `${id}@example.com`,
    phone: "+30 690 000 0000",
    message: null,
    interests: ["trial"],
    campaign: null,
    consent,
    converted_at: null,
    created_at: daysAgo(2),
    last_contacted_at: null,
    locale: "el",
    lost_reason: null,
    next_task: null,
    owner: null,
    person: null,
    stage_changed_at: daysAgo(2),
    ...extra,
  };
}

const leads = [
  lead("lead-1", "Eleni Papadopoulou", "new"),
  lead("lead-2", "Giorgos Katsaros", "trial", {
    owner: { user_id: "owner-1", display_name: "Apostolos", handle: "apostolos" },
  }),
  lead("lead-3", "Anna Mavrou", "offer"),
];
const counts = { new: 1, trial: 1, offer: 1, converted: 4, lost: 2 };

function detail(id: string, events: Array<Record<string, unknown>> = []) {
  const found = leads.find((entry) => entry.id === id)!;
  return {
    lead: found,
    tasks: [],
    events: [
      { id: `${id}-e1`, kind: "created", at: found.created_at, actor: null, data: { source: "website_form" } },
      ...events,
    ],
  };
}

async function asOwner(page: Page, writes: Write[], extra?: (path: string, method: string, route: Route) => Promise<void> | null) {
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
    if (path === "/api/admin/users") return json(route, { users: [], total: 0 });
    const handled = extra?.(path, method, route);
    if (handled) return handled;
    return json(route, {});
  });
}

test.describe("leads (staff)", () => {
  test("the kanban shows the open stages with counts, and a card opens its panel where «Contacted» is logged", async ({ page }) => {
    const writes: Write[] = [];
    let contacted = false;
    await asOwner(page, writes, (path, method, route) => {
      if (path === "/api/admin/leads" && method === "GET") return json(route, { leads, counts });
      if (path === "/api/admin/leads/lead-1" && method === "GET") {
        return json(route, detail("lead-1", contacted ? [{ id: "e2", kind: "contacted", at: new Date().toISOString(), actor: { user_id: "owner-1", display_name: "Apostolos" }, data: { channel: "email" } }] : []));
      }
      if (path === "/api/admin/leads/lead-1/contacted") {
        contacted = true;
        return json(route, detail("lead-1", [{ id: "e2", kind: "contacted", at: new Date().toISOString(), actor: { user_id: "owner-1", display_name: "Apostolos" }, data: { channel: "email" } }]));
      }
      return null;
    });
    await page.goto("/admin/leads");

    await expect(page.getByRole("heading", { name: "Leads", level: 1 })).toBeVisible();
    // The view switch counts the open leads together, and the closed lists apart.
    await expect(page.getByRole("tab", { name: "Open (3)" })).toHaveAttribute("aria-selected", "true");
    await expect(page.getByRole("tab", { name: "Became a member (4)" })).toBeVisible();
    await expect(page.getByRole("tab", { name: "Lost (2)" })).toBeVisible();

    const board = page.getByTestId("leads-board");
    for (const [stage, label, name] of [
      ["new", "New (1)", "Eleni Papadopoulou"],
      ["trial", "Trial (1)", "Giorgos Katsaros"],
      ["offer", "Offer (1)", "Anna Mavrou"],
    ] as const) {
      const column = board.locator(`section[data-stage="${stage}"]`);
      await expect(column.getByRole("heading", { name: label })).toBeVisible();
      await expect(column.getByRole("button", { name: new RegExp(name) })).toBeVisible();
    }
    await expect(board.getByTestId("lead-card-lead-1")).toContainText("No owner");
    await expect(board.getByTestId("lead-card-lead-2")).toContainText("Owner: Apostolos");

    await board.getByTestId("lead-card-lead-1").click();
    const panel = page.getByRole("dialog", { name: "Eleni Papadopoulou" });
    await expect(panel.getByTestId("lead-panel")).toBeVisible();
    await expect(panel.getByTestId("lead-history")).toContainText("Came in from: Website");
    await expect(panel.getByRole("link", { name: "Call" })).toHaveAttribute("href", "tel:+306900000000");
    await expect(panel.getByRole("radio", { name: "New" })).toHaveAttribute("aria-checked", "true");

    await panel.getByRole("button", { name: "Contacted" }).click();
    await panel.getByRole("radio", { name: "Email" }).click();
    await panel.getByTestId("lead-contacted-save").click();
    await expect
      .poll(() => writes.find((write) => write.path === "/api/admin/leads/lead-1/contacted"))
      .toEqual({ path: "/api/admin/leads/lead-1/contacted", method: "POST", body: { channel: "email" } });
    await expect(panel.getByTestId("lead-history")).toContainText("Contacted: Email");
    await expect(panel.getByTestId("lead-history")).toContainText("Apostolos");
  });

  test("/admin/leads?lead=<id> opens that lead's panel straight away (ADR-388 notification link)", async ({ page }) => {
    const reads: string[] = [];
    await asOwner(page, [], (path, method, route) => {
      if (path === "/api/admin/leads" && method === "GET") return json(route, { leads, counts });
      if (path === "/api/admin/leads/lead-2") {
        reads.push(path);
        return json(route, detail("lead-2"));
      }
      return null;
    });
    await page.goto("/admin/leads?lead=lead-2");

    const panel = page.getByRole("dialog", { name: "Giorgos Katsaros" });
    await expect(panel.getByTestId("lead-panel")).toBeVisible();
    await expect(panel.getByRole("radio", { name: "Trial" })).toHaveAttribute("aria-checked", "true");
    expect(reads).toContain("/api/admin/leads/lead-2");

    await panel.getByRole("button", { name: "Close" }).first().click();
    await expect(panel).toBeHidden();
    await expect(page.getByTestId("leads-board")).toBeVisible();
  });
});

test.describe("members at risk", () => {
  test("a row says why in plain words, and «Contacted» posts the channel", async ({ page }) => {
    const writes: Write[] = [];
    const levelSince = daysAgo(3);
    const member = (contactedAt: string | null) => ({
      user_id: "member-9",
      person: { user_id: "member-9", display_name: "Nikos Pappas", handle: "nikos" },
      level: "high",
      level_since: levelSince,
      computed_at: daysAgo(0),
      score: 80,
      reasons: [
        { code: "absent", facts: { days: 21 }, points: 40 },
        { code: "package_ending", facts: { days: 5 }, points: 20 },
      ],
      suggested_action: "personal_message",
      contacted_at: contactedAt,
      contacted_by: contactedAt ? { user_id: "owner-1", display_name: "Apostolos" } : null,
      snoozed_until: null,
      win_back_queued_at: null,
    });
    let contactedAt: string | null = null;
    await asOwner(page, writes, (path, _method, route) => {
      if (path === "/api/admin/members-at-risk") return json(route, { computed_at: daysAgo(0), counts: { high: 1, medium: 0 }, members: [member(contactedAt)] });
      if (path === "/api/admin/members-at-risk/member-9/contacted") {
        contactedAt = new Date().toISOString();
        return json(route, { member: member(contactedAt) });
      }
      return null;
    });
    await page.goto("/admin/users/at-risk");

    await expect(page.getByRole("heading", { name: "At risk", level: 1 })).toBeVisible();
    await expect(page.getByRole("tab", { name: "High (1)" })).toBeVisible();
    const row = page.getByTestId("risk-row-member-9");
    await expect(row).toContainText("Nikos Pappas");
    await expect(row).toContainText("High");
    await expect(row).toContainText("Hasn't come for 21 days");
    await expect(row).toContainText("The package ends in 5 days");
    await expect(row).toContainText("Send a personal message");
    // No score is shown (ADR-347).
    await expect(row).not.toContainText("80");

    await row.getByTestId("risk-contacted-member-9").click();
    await page.getByRole("menu", { name: "Contacted" }).getByRole("menuitem", { name: "Phone" }).click();
    await expect
      .poll(() => writes.find((write) => write.path === "/api/admin/members-at-risk/member-9/contacted"))
      .toEqual({ path: "/api/admin/members-at-risk/member-9/contacted", method: "POST", body: { channel: "phone" } });
    await expect(row).toContainText("Contacted · Apostolos");
    await expect(row.getByTestId("risk-contacted-member-9")).toHaveCount(0);

    await expect(page.getByRole("link", { name: "Automations" })).toHaveAttribute("href", /\/metrics\?tab=automations$/);
  });
});

test.describe("automations", () => {
  const recipe = (key: string, enabled: boolean, settings: Record<string, unknown> = {}) => ({
    key,
    enabled,
    audience: ["member"],
    body: null,
    subject: null,
    channels: ["in_app", "email"],
    default_body: "Hello {first_name}",
    default_subject: "Hello",
    default_channels: ["in_app", "email"],
    default_delay_minutes: 0,
    delay_minutes: 0,
    purpose: "service",
    settings,
    stats: {},
    trigger: key === "missed_classes" ? "daily" : "membership.started",
    updated_at: null,
  });

  test("the old address redirects to the «Automations» tab, where a recipe is switched on", async ({ page }) => {
    const writes: Write[] = [];
    await asOwner(page, writes, (path, method, route) => {
      if (path === "/api/admin/automations" && method === "GET") {
        return json(route, {
          channels: ["in_app", "email", "sms"],
          placeholders: ["{first_name}", "{box}"],
          stats_days: 30,
          recipes: [recipe("welcome", false), recipe("missed_classes", true, { days_absent: 10 })],
        });
      }
      if (path === "/api/admin/automations/welcome" && method === "PATCH") return json(route, { recipe: recipe("welcome", true) });
      return null;
    });
    await page.goto("/admin/metrics/automations");

    await expect(page).toHaveURL(/\/admin\/metrics\?tab=automations$/);
    await expect(page.getByRole("tab", { name: "Automations" })).toHaveAttribute("aria-selected", "true");
    const tab = page.getByTestId("automations-tab");
    const list = tab.getByTestId("automations-list");
    await expect(list.getByTestId("recipe-welcome")).toContainText("Welcome");
    await expect(list.getByTestId("recipe-welcome")).toContainText("When someone becomes a box member");
    await expect(list.getByTestId("recipe-missed_classes")).toContainText("When they haven't trained for 10 days");

    const welcome = list.getByRole("switch", { name: "Welcome: on or off" });
    await expect(welcome).toHaveAttribute("aria-checked", "false");
    await welcome.click();
    await expect
      .poll(() => writes.find((write) => write.path.startsWith("/api/admin/automations/welcome")))
      .toEqual({ path: "/api/admin/automations/welcome?locale=en", method: "PATCH", body: { enabled: true } });
    await expect(welcome).toHaveAttribute("aria-checked", "true");
  });
});

// The public box page (no website): the «I'm interested» card for visitors.

const slug = "leads-e2e-box";
const box = { organization_id: "org-1", slug, name: "Box Kypseli", logo_url: null, primary_color: "#D9743D" };
const publicBox = {
  box,
  followers_count: 3,
  profile: { about: "A friendly box.", disciplines: ["crossfit"], audiences: [], services: [], amenities: [], languages: [], cover: null, photos: [], coaches: [] },
  locations: [],
};

test.describe("the visitor's «I'm interested»", () => {
  let server: Server;

  test.beforeAll(async () => {
    server = createServer((request, response) => {
      if (request.url?.startsWith(`/api/public/boxes/${slug}`)) {
        response.writeHead(200, { "content-type": "application/json" });
        response.end(JSON.stringify(publicBox));
        return;
      }
      // No website for this box (ADR-388): the plain box page with the enquiry card.
      response.writeHead(404, { "content-type": "application/json" });
      response.end(JSON.stringify({ error: "not_found" }));
    });
    await new Promise<void>((resolve) => server.listen(stubApiPort, "127.0.0.1", resolve));
  });

  test.afterAll(async () => {
    await new Promise((resolve) => server.close(resolve));
  });

  test("a signed-out visitor sends an enquiry with the contact consent", async ({ page }) => {
    const sent: unknown[] = [];
    await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
    await page.route("**/api/**", (route) => json(route, {}));
    await page.route("**/api/auth/refresh", (route) => json(route, { error: "unauthorized" }, 401));
    await page.route(`**/api/public/boxes/${slug}/leads`, (route) => {
      sent.push(route.request().postDataJSON());
      return json(route, { status: "received" }, 202);
    });
    await page.goto(`/b/${slug}`);

    await expect(page.getByText("Want to try Box Kypseli or ask something?")).toBeVisible();
    await page.getByTestId("enquiry-open").click();
    const dialog = page.getByRole("dialog", { name: "I'm interested" });
    await dialog.getByLabel("Name").fill("Maria Nikolaou");
    await dialog.getByLabel("Mobile or email").fill("maria@example.com");
    await dialog.getByRole("button", { name: "Trial workout" }).click();
    await expect(dialog.getByRole("button", { name: "Trial workout" })).toHaveAttribute("aria-pressed", "true");
    await dialog.getByLabel("Message").fill("Evenings suit me.");

    // The yes to being contacted is required; nothing is sent without it.
    await dialog.getByTestId("enquiry-send").click();
    await expect(dialog.getByText("Tick this so the box can answer you.")).toBeVisible();
    expect(sent).toEqual([]);

    await dialog.getByTestId("enquiry-consent").check();
    await dialog.getByTestId("enquiry-send").click();
    await expect(page.getByTestId("enquiry-sent")).toContainText("Got it!");
    await expect(page.getByTestId("enquiry-sent")).toContainText("Box Kypseli will get back to you soon");
    expect(sent).toEqual([
      expect.objectContaining({
        name: "Maria Nikolaou",
        email: "maria@example.com",
        message: "Evenings suit me.",
        interests: ["trial"],
        kind: "trial",
        source: "form",
        locale: "en",
        website: "",
        consent: { contact: true, marketing: false, text_version: "2027-05" },
        form_started_at: expect.any(String),
      }),
    ]);
    expect(sent[0]).not.toHaveProperty("phone");
  });
});
