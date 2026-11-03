import { expect, test, type Page, type Request } from "./support/test";

// ADR-366, W7 screens 1 and 12: the public status page (status.palee.app,
// /status as the fallback) with 30 days per part on a phone and 90 on a
// desktop, the problem that is open now with its latest update, earlier
// problems and the email sign-up (double opt-in); the in-app strip shown only
// to people who use the affected part, with no close button, gone once the
// problem is resolved. The API is stubbed; every route not listed answers an
// empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");
const KEYS = ["app", "search", "files", "email", "payments", "fiscal"] as const;

const incident = (overrides: Record<string, unknown> = {}) => ({
  id: "i1",
  kind: "incident",
  title: "Καθυστερήσεις στα email",
  title_en: "Email delays",
  locale: "el",
  en_source: "auto",
  impact: "minor",
  status: "investigating",
  components: ["email"],
  scheduled_for: null,
  scheduled_until: null,
  started_at: "2026-11-02T19:12:00Z",
  resolved_at: null,
  updates: [
    {
      id: "u1",
      status: "investigating",
      body: "Τα αποδεικτικά αργούν έως μία ώρα.",
      body_en: "Receipts are delayed by up to an hour.",
      locale: "el",
      en_source: "auto",
      created_at: "2026-11-02T19:20:00Z",
    },
  ],
  ...overrides,
});

const overview = (active: unknown[]) => ({
  status: active.length ? "partial_outage" : "operational",
  generated_at: "2026-11-02T19:30:00Z",
  components: KEYS.map((key) => ({ key, status: key === "email" && active.length ? "degraded" : "operational", checked_at: "2026-11-02T19:30:00Z" })),
  active,
  upcoming: [],
});

const history = (days: number) => ({
  days,
  from: "2026-08-05",
  to: "2026-11-02",
  generated_at: "2026-11-02T19:30:00Z",
  components: KEYS.map((key) => ({
    key,
    uptime_percent: 100,
    days: Array.from({ length: days }, (_, i) => ({
      date: new Date(Date.UTC(2026, 10, 2 - (days - 1) + i)).toISOString().slice(0, 10),
      status: "operational",
      uptime_percent: 100,
    })),
  })),
  incidents: [incident({ id: "old", title: "Πληρωμές", title_en: "Payments failing", components: ["payments"], status: "resolved", started_at: "2026-10-20T10:00:00Z", resolved_at: "2026-10-20T10:45:00Z" })],
});

async function publicStatus(page: Page, active: unknown[]) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
  await page.route("**/api/public/status", (route) => route.fulfill(json(overview(active))));
  await page.route("**/api/public/status/history?**", (route) => {
    const days = Number(new URL(route.request().url()).searchParams.get("days") ?? "90");
    return route.fulfill(json(history(days)));
  });
}

async function signedInMember(page: Page, role: string) {
  const user = {
    id: "member-1",
    nickname: "Maria",
    role: "member",
    email: "maria@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role, settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: `stub.${payload}.signature`, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role,
          roles: [role],
          capabilities: {},
          organization: { id: "org-1", slug: "box1", name: "Box One", provider_kind: "gym", timezone: "UTC" },
          settings: { brand_name: "Box One", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

test.describe("public status page", () => {
  test("a desktop sees 90 days per part, the open problem with its latest update, and earlier problems", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await publicStatus(page, [incident()]);
    await page.goto("/status");

    // With an open problem, the problem card itself carries the overall state.
    const open = page.getByTestId("status-incident");
    await expect(open).toContainText("Partial problem");
    await expect(open).toContainText("Email delays");
    await expect(open).toContainText("Receipts are delayed by up to an hour.");
    await expect(open).toContainText("automatic translation");
    await expect(page.getByTestId("status-components")).toHaveAttribute("data-days", "90");
    await expect(page.getByRole("img", { name: "Files and photos: the last 90 days" })).toBeVisible();
    await expect(page.getByTestId("status-past")).toContainText("Payments failing");
  });

  test("a phone sees 30 days per part", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await publicStatus(page, []);
    await page.goto("/status");
    await expect(page.getByTestId("status-now")).toContainText("Everything works");
    await expect(page.getByTestId("status-components")).toHaveAttribute("data-days", "30");
    await expect(page.getByText("Last 30 days")).toBeVisible();
  });

  test("the email sign-up asks for confirmation first, and the confirm link turns it on", async ({ page }) => {
    await publicStatus(page, []);
    const sent: Array<Record<string, unknown>> = [];
    await page.route("**/api/public/status/subscriptions", (route) => {
      sent.push(bodyOf(route.request()));
      return route.fulfill(json({ status: "pending" }, 202));
    });
    await page.route("**/api/public/status/subscriptions/confirm", (route) => route.fulfill(json({ status: "confirmed" })));

    await page.goto("/status");
    const form = page.getByTestId("status-subscribe");
    await form.getByLabel("Email").fill("not-an-email");
    await form.getByRole("button", { name: "Sign up" }).click();
    await expect(form.getByText("Write a valid email address.")).toBeVisible();
    expect(sent).toHaveLength(0);

    await form.getByLabel("Email").fill("maria@example.com");
    await form.getByRole("button", { name: "Sign up" }).click();
    await expect(form.getByText("We sent a confirmation email to maria@example.com.", { exact: false })).toBeVisible();
    expect(sent[0]).toMatchObject({ email: "maria@example.com", locale: "en" });

    await page.goto("/status?confirm=token-1");
    await expect(page.getByTestId("status-link-result")).toContainText("Status emails are on.");
  });
});

test.describe("in-app status strip", () => {
  test("shows a payments problem to a member, with no close button, and goes when it is resolved", async ({ page }) => {
    await publicStatus(page, [incident({ components: ["payments"], title_en: "Payments failing" })]);
    await signedInMember(page, "member");
    await page.goto("/");

    const strip = page.getByTestId("service-status-strip");
    await expect(strip).toContainText("Payments failing");
    await expect(strip.getByRole("button")).toHaveCount(0);
    await expect(strip.getByRole("link", { name: "Details" })).toHaveAttribute("href", "/status");

    await page.route("**/api/public/status", (route) => route.fulfill(json(overview([]))));
    await page.reload();
    await expect(page.getByTestId("service-status-strip")).toHaveCount(0);
  });

  test("does not bother a member with a fiscal problem they never use", async ({ page }) => {
    await publicStatus(page, [incident({ components: ["fiscal"] })]);
    await signedInMember(page, "member");
    await page.goto("/");
    await expect(page.getByRole("navigation").first()).toBeVisible();
    await expect(page.getByTestId("service-status-strip")).toHaveCount(0);
  });
});
