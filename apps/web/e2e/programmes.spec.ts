import { expect, test, type Page, type Route } from "./support/test";

// W8 / CP-D4 programme marketplace (ADR-370/371): the staff list of
// «Προγράμματα προπόνησης» with «Νέο πρόγραμμα», the public
// «Αγορά προγραμμάτων» catalogue with its goal chips, a programme's page
// (board 2κ/2μ A) and the buyer's days (board 3κ/3μ A, ADR-540). The API is
// stubbed.

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

function staffProgramme(id: string, title: string, status: "draft" | "published", extra: Record<string, unknown> = {}) {
  return {
    id,
    title,
    status,
    draft_weeks: 6,
    price_cents: status === "published" ? 4900 : null,
    currency: "EUR",
    version: status === "published" ? { id: `${id}-v1`, number: 1, weeks: 6 } : null,
    reviews: { average: null, count: 0 },
    sales: { buyers: status === "published" ? 3 : 0 },
    ...extra,
  };
}

const marketplace = [
  {
    id: "p-strength",
    title: "Strength in 6 weeks",
    goal: "strength",
    level: "intermediate",
    weeks: 6,
    price_cents: 4900,
    currency: "EUR",
    rating_average: null,
    rating_count: 0,
    organization_name: "Box Kypseli",
    organization_slug: "kypseli",
  },
  {
    id: "p-engine",
    title: "Engine builder",
    goal: "endurance",
    level: "beginner",
    weeks: 8,
    price_cents: 3900,
    currency: "EUR",
    rating_average: 4.6,
    rating_count: 12,
    organization_name: "Box Pagrati",
    organization_slug: "pagrati",
  },
];

async function stubApi(page: Page, writes: Write[], extra?: (path: string, method: string, route: Route, url: URL) => Promise<void> | null) {
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
    const handled = extra?.(path, method, route, url);
    if (handled) return handled;
    return json(route, {});
  });
}

test.describe("programmes (staff)", () => {
  test("the list shows each programme with its status, and «New programme» creates a draft and opens it", async ({ page }) => {
    const writes: Write[] = [];
    await stubApi(page, writes, (path, method, route) => {
      if (path === "/api/admin/programmes" && method === "GET") {
        return json(route, { programmes: [staffProgramme("prog-1", "Strength in 6 weeks", "published"), staffProgramme("prog-2", "Summer engine", "draft")] });
      }
      if (path === "/api/admin/programmes" && method === "POST") {
        return json(route, { programme: staffProgramme("prog-3", "Gymnastics basics", "draft", { draft_weeks: 4 }) }, 201);
      }
      if (path === "/api/admin/programmes/prog-3") return json(route, { programme: staffProgramme("prog-3", "Gymnastics basics", "draft", { draft_weeks: 4 }) });
      return null;
    });
    await page.goto("/admin/programmes");

    await expect(page.getByRole("heading", { name: "Training programmes", level: 1 })).toBeVisible();
    await expect(page.getByTestId("programme-row-prog-1")).toContainText("Strength in 6 weeks");
    await expect(page.getByTestId("programme-row-prog-1")).toContainText("3 buyers");
    await expect(page.getByTestId("programme-row-prog-2")).toContainText("Summer engine");

    await page.getByRole("button", { name: "New programme" }).click();
    const dialog = page.getByTestId("programme-new-dialog");
    await dialog.getByLabel("Title").fill("Gymnastics basics");
    await dialog.getByRole("button", { name: "Create" }).click();

    await expect(page).toHaveURL(/\/admin\/programmes\/prog-3$/);
    const created = writes.find((write) => write.path === "/api/admin/programmes" && write.method === "POST");
    expect(created?.body).toEqual({ title: "Gymnastics basics", draft_weeks: 4 });
  });
});

test.describe("programme store (public)", () => {
  test("the catalogue lists programmes from every box, and a goal chip filters the list", async ({ page }) => {
    const queries: string[] = [];
    await stubApi(page, [], (path, _method, route, url) => {
      if (path === "/api/public/programmes") {
        queries.push(url.search);
        const goal = url.searchParams.get("goal");
        return json(route, { programmes: goal ? marketplace.filter((entry) => entry.goal === goal) : marketplace });
      }
      return null;
    });
    await page.goto("/programmes");

    await expect(page.getByRole("heading", { name: "Programme store", level: 1 })).toBeVisible();
    await expect(page.getByTestId("programme-card-p-strength")).toContainText("Box Kypseli");
    await expect(page.getByTestId("programme-card-p-engine")).toContainText("Box Pagrati");
    await expect(page.getByTestId("programme-card-p-strength").getByRole("link", { name: "See it" })).toHaveAttribute(
      "href",
      "/b/kypseli/programmes/p-strength",
    );

    await page.getByRole("radio", { name: "Endurance" }).click();
    await expect(page.getByTestId("programme-card-p-strength")).toHaveCount(0);
    await expect(page.getByTestId("programme-card-p-engine")).toBeVisible();
    expect(queries).toContain("?goal=endurance");
  });
});

const publicProgramme = {
  id: "p-strength",
  title: "Strength in 6 weeks",
  goal: "strength",
  level: "intermediate",
  weeks: 6,
  sessions_per_week: 4,
  minutes_per_session: 45,
  main_equipment: ["barbell"],
  refund_policy: "before_start",
  cover_url: null,
  price_cents: 3900,
  currency: "EUR",
  reviews: { average: 4.8, count: 23 },
  latest_reviews: [{ id: "r1", rating: 5, status: "published", version_number: 1, body: "Added 15 kg to my squat.", author: { nickname: "Nikos" } }],
  preview: [
    { day: 0, week: 1, weekday: 0, title: "Back squat 5×5" },
    { day: 1, week: 1, weekday: 1, title: "Fran" },
  ],
  week_outline: [1, 2, 3, 4, 5, 6].map((week) => ({ week, sessions: 4 })),
};

test.describe("programme page (public)", () => {
  test("shows the facts, the free days, the reviews, the weeks and the buy bar", async ({ page }) => {
    await stubApi(page, [], (path, _method, route) => {
      if (path === "/api/public/boxes/kypseli/programmes/p-strength") return json(route, { box: { name: "Box Kypseli", slug: "kypseli" }, programme: publicProgramme });
      return null;
    });
    await page.goto("/b/kypseli/programmes/p-strength");

    await expect(page.getByRole("heading", { name: "Strength in 6 weeks", level: 1 })).toBeVisible();
    await expect(page.getByTestId("programme-fact-minutes")).toContainText("45′");
    await expect(page.getByTestId("programme-fact-equipment")).toContainText("Barbell");
    await expect(page.getByTestId("programme-reviews")).toContainText("Added 15 kg to my squat.");
    await expect(page.getByTestId("programme-week-1")).toContainText("Fran");
    await expect(page.getByTestId("programme-week-1")).toContainText("2 locked WODs");
    await expect(page.getByTestId("programme-week-3")).toContainText("Weeks 3–6");
    await expect(page.getByTestId("programme-faq")).toContainText("When do I start?");
    await expect(page.locator('[data-testid^="programme-buy-open"]:visible')).toHaveText("Buy");
  });

  test("survives a stub that answers {}", async ({ page }) => {
    await stubApi(page, []);
    await page.goto("/b/kypseli/programmes/p-strength");
    await expect(page.getByText("This programme is not available.")).toBeVisible();
  });
});

const purchase = { id: "pu-1", programme_id: "p-strength", title: "Strength in 6 weeks", status: "active", starts_on: "2026-10-26", ends_on: "2026-12-06", currency: "EUR", version_number: 1 };

function purchaseDays(moved: boolean) {
  const wod = (id: string, title: string, done = false) => ({ workout_id: id, assigned_workout_id: `a-${id}`, done, title, summary: null });
  return {
    purchase_id: "pu-1",
    starts_on: "2026-10-26",
    today: "2026-11-05",
    weeks: 6,
    progress: { done: 1, total: 24, skipped: 0, behind: moved ? 0 : 1, remaining: 23 },
    behind: moved ? null : { day: 8, week: 2, weekday: 1, date: "2026-11-03", can_do_today: true, can_skip: true },
    days: [
      { day: 7, week: 2, weekday: 0, date: "2026-11-02", status: "done", workouts: [wod("w7", "Front squat 5×3", true)] },
      moved
        ? { day: 8, week: 2, weekday: 1, date: "2026-11-05", status: "today", workouts: [wod("w8", "Helen")] }
        : { day: 8, week: 2, weekday: 1, date: "2026-11-03", status: "behind", workouts: [wod("w8", "Helen")] },
      { day: 10, week: 2, weekday: 3, date: moved ? "2026-11-07" : "2026-11-05", status: moved ? "upcoming" : "today", workouts: [wod("w10", "Deadlift 5×5")] },
    ],
  };
}

test.describe("programme days (buyer)", () => {
  test("«Do it today» moves the day left behind and the page shows the new days", async ({ page }) => {
    const writes: Write[] = [];
    let moved = false;
    await stubApi(page, writes, (path, method, route) => {
      if (path === "/api/me/programme-purchases/pu-1" && method === "GET") return json(route, { purchase });
      if (path === "/api/me/programme-purchases/pu-1/days" && method === "GET") return json(route, purchaseDays(moved));
      if (path === "/api/me/programme-purchases/pu-1/days/do-today" && method === "POST") {
        moved = true;
        return json(route, purchaseDays(true));
      }
      return null;
    });
    await page.goto("/box/programmes/pu-1");

    await expect(page.getByTestId("programme-progress")).toHaveText("1 / 24 sessions");
    const behind = page.getByTestId("programme-behind");
    await expect(behind).toContainText("Day 2 fell behind");
    await expect(page.getByTestId("programme-day-card")).toContainText("Deadlift 5×5");
    await expect(page.getByTestId("programme-day-card").getByRole("link", { name: "Start" })).toHaveAttribute("href", "/box/workouts?open_assignment=a-w10");

    await behind.getByRole("button", { name: "Do it today" }).click();
    await expect(page.getByTestId("programme-behind")).toHaveCount(0);
    expect(writes.find((write) => write.path.endsWith("/days/do-today"))?.body).toEqual({ day: 8 });
    await expect(page.getByTestId("programme-day-card")).toContainText("Helen");
  });

  test("survives stubs that answer {}", async ({ page }) => {
    await stubApi(page, []);
    await page.goto("/box/programmes/pu-1");
    await expect(page.getByTestId("my-programme")).toBeVisible();
  });
});
