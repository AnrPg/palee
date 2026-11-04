import { expect, test, type Page } from "./support/test";

// v3.1 W5 «Προπόνηση και πάτωμα» (ADR-356..359, ADR-389, ANR mockups d2 A,
// d6 A, e4 A): the #wod leaderboard chips with the percentile on the
// member's own row, the fitness profile on Πρόοδος (version 2, ADR-395), and the calendar offer
// after the first booking. The API is stubbed; every route not listed
// answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const user = {
  id: "member-1",
  nickname: "Maria",
  role: "member",
  email: "member-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};

function tokenFor() {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

function localDate(days = 0) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

async function stubApi(page: Page) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "member",
          roles: ["member"],
          capabilities: {},
          home_location_id: "loc-1",
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", timezone: "Europe/Athens" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/me/entitlement", (route) => route.fulfill(json({ entitlement: null })));
}

const gymClub = {
  id: "club-1",
  kind: "gym",
  name: "Box Kypseli",
  organization_id: "org-1",
  organization_slug: "kypseli",
  role: "member",
  notify_level: "all",
  logo_url: null,
  primary_color: null,
  channels: [{ id: "ch-wod", kind: "wod", name: null, write_policy: "members", membership: "everyone", joined: true, can_post: true, can_leave: false }],
};

const row = (userId: string, rank: number, value: string, extra: Record<string, unknown> = {}) => ({
  user_id: userId,
  me: false,
  nickname: userId,
  avatar_url: null,
  rank,
  percentile: null,
  top_percent: null,
  value,
  unit: null,
  scale_level_slug: "rx",
  ...extra,
});

test.describe("training floor (v3.1 W5)", () => {
  test("the #wod leaderboard: my chips on top, my percentile on my row, the rest under «Advanced» (mockup d2 A)", async ({ page }) => {
    // Desktop layout: on a phone this picker is a combobox (SegmentPicker collapses).
    await page.setViewportSize({ width: 1280, height: 800 });
    await stubApi(page);
    const asked: URLSearchParams[] = [];
    await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [gymClub] })));
    await page.route("**/api/me/feed**", (route) => route.fulfill(json({ posts: [], pinned: [], next_cursor: null })));
    await page.route("**/api/org/*/community/wod-today**", (route) =>
      route.fulfill(
        json({
          date: localDate(),
          channel_id: "ch-wod",
          classes: [],
          leaderboard: [],
          logged_by_me: true,
          score: { id: "score-1", name: "Time", score_type: "time", unit: null },
          workout: { id: "wod-1", title: "Fran", type: "for_time" },
        }),
      ),
    );
    await page.route("**/api/org/kypseli/workouts/wod-1/leaderboard**", (route) => {
      const params = new URL(route.request().url()).searchParams;
      asked.push(params);
      const me = row("member-1", 4, "4:10", { me: true, nickname: "Maria", percentile: 70, top_percent: 30 });
      route.fulfill(
        json({
          opted_in: true,
          filters: { date: localDate(), window: "day", scope: "box", buddies: false },
          me,
          rows: [row("Eleni", 1, "3:02"), row("Nikos", 2, "3:40"), row("Petros", 3, "3:55"), me],
          total: 10,
          profile: { division: "women", birth_year: 1989 },
          options: {
            age_groups: ["35_39"],
            divisions: ["women", "men"],
            scales: [{ slug: "rx", label: "RX" }],
            scopes: ["box", "branch"],
            windows: ["day", "week", "month", "year", "all"],
          },
        }),
      );
    });

    await page.goto("/clubs/club-1");
    const board = page.getByTestId("wod-leaderboard");
    await expect(board).toBeVisible();
    const chips = board.getByRole("group", { name: /filter/i });
    await expect(chips.getByRole("button")).toHaveText(["Everyone", "Women", /35–39/, "RX"]);
    await expect(chips.getByRole("button", { name: "Everyone" })).toHaveAttribute("aria-pressed", "true");
    await expect(board.getByTestId("wod-leaderboard-me")).toContainText("top 30%");
    await expect(board.getByText(/top \d+%/)).toHaveCount(1);

    await chips.getByRole("button", { name: "Women" }).click();
    await expect.poll(() => asked.at(-1)?.get("division")).toBe("women");

    // Time window, branch and buddies wait under «Advanced».
    await expect(board.getByRole("radiogroup")).toHaveCount(0);
    await board.getByTestId("wod-leaderboard-advanced").getByRole("button").first().click();
    await board.getByRole("radio", { name: "Month" }).click();
    await expect.poll(() => asked.at(-1)?.get("window")).toBe("month");
  });

  test("Progress shows a bar per domain with the change next to it and a stepped «Why?» (mockup d6 A, fitness v2 A)", async ({ page }) => {
    await stubApi(page);
    const asked: URLSearchParams[] = [];
    await page.route((url) => url.pathname.endsWith("/api/me/fitness-profile"), (route) => {
      asked.push(new URL(route.request().url()).searchParams);
      return route.fulfill(
        json({
          algorithm: { id: "fitness-profile", version: 2 },
          benchmarks_known: 3,
          division: null,
          neutral_standards: true,
          injury_caution: false,
          overall: { score: 58, domains_scored: 2, reason: "mean_of_domains", change: 4 },
          focus: [{ kind: "weakest_domain", domain: "gymnastics" }],
          display: { mode: "all", set_by: "self" },
          settings: { body_weight_kg: 60, birth_year: null, display: "all" },
          inputs: { body_weight_kg: 60, age_band: null, age_percent: null, age_ready: false },
          period_from: localDate(-84),
          domains: [
            {
              domain: "strength",
              score: 66,
              previous_score: 60,
              change: 6,
              confidence: "medium",
              stale: false,
              reasons: [
                {
                  benchmark: "back_squat",
                  name: "Back squat",
                  domain: "strength",
                  value: 77,
                  unit: "kg",
                  points: 66,
                  estimated: true,
                  stale: false,
                  age_days: 12,
                  beaten_on: localDate(-12),
                  load: 70,
                  reps: 3,
                  basis: "body_weight",
                  ratio: 1.28,
                  body_weight_kg: 60,
                  age_band: null,
                  age_percent: null,
                  anchors: [
                    { value: 0.7, points: 20 },
                    { value: 1.1, points: 50 },
                    { value: 1.35, points: 75 },
                    { value: 1.7, points: 95 },
                  ],
                  next: { points: 75, value: 81 },
                },
              ],
            },
            { domain: "gymnastics", score: 40, previous_score: 40, change: 0, confidence: "low", stale: false, reasons: [] },
          ],
        }),
      );
    });

    await page.goto("/journal/progress");
    const card = page.getByTestId("fitness-profile");
    await expect(card.getByRole("heading", { name: "Fitness level" })).toBeVisible();
    await expect(card.getByRole("meter")).toHaveCount(5);
    await expect.poll(() => asked.at(-1)?.get("period")).toBe("12w");
    const strength = card.getByTestId("fitness-domain-strength");
    await expect(strength.getByTestId("fitness-change")).toContainText("▲ +6");
    await expect(strength.getByTestId("fitness-previous-tick")).toBeAttached();
    await strength.getByRole("button", { name: /Why\?/ }).click();
    const why = strength.getByTestId("fitness-why-back_squat");
    await expect(why).toContainText("70 kg × (1 + 3 ÷ 30) ≈ 77 kg");
    await expect(why).toContainText("77 kg ÷ 60 kg = 1.28 ×");
    await expect(why).toContainText("4 kg more");
    await expect(card.getByTestId("fitness-focus")).toContainText("What to work on");

    // The period comes from Progress's own period bar.
    await page.getByRole("button", { name: "6 months" }).click();
    await expect.poll(() => asked.at(-1)?.get("period")).toBe("6m");
  });

  test("the card shows only progress when the coach set it, and saves the member's own choice (fitness v2 §4 A)", async ({ page }) => {
    await stubApi(page);
    const saved: unknown[] = [];
    await page.route("**/api/me/fitness-profile/settings", async (route) => {
      saved.push(route.request().postDataJSON());
      await route.fulfill(json({ body_weight_kg: 72, birth_year: null, display: "none" }));
    });
    await page.route((url) => url.pathname.endsWith("/api/me/fitness-profile"), (route) =>
      route.fulfill(
        json({
          algorithm: { id: "fitness-profile", version: 2 },
          benchmarks_known: 3,
          division: null,
          neutral_standards: true,
          injury_caution: false,
          overall: null,
          focus: [{ kind: "untested_domain", domain: "power" }],
          display: { mode: "progress_only", set_by: "coach" },
          settings: { body_weight_kg: null, birth_year: null, display: "all" },
          inputs: { body_weight_kg: null, age_band: null, age_percent: null, age_ready: false },
          period_from: localDate(-84),
          domains: [
            { domain: "strength", tested: true, direction: "up" },
            { domain: "power", tested: false, direction: null },
          ],
        }),
      ),
    );

    await page.goto("/journal/progress");
    const card = page.getByTestId("fitness-profile");
    await expect(card.getByTestId("fitness-set-by-coach")).toHaveText("Your coach set this");
    await expect(card.getByTestId("fitness-domain-strength")).toContainText("improved");
    await expect(card.getByRole("meter")).toHaveCount(0);

    await card.getByTestId("fitness-profile-advanced").getByRole("button").first().click();
    await expect(card.getByLabel("Year of birth")).toHaveCount(0);
    await expect(card.getByTestId("fitness-coach-limit")).toContainText("Your coach chose “Only progress”");
    await card.getByLabel("Body weight").fill("72");
    await card.getByRole("radio", { name: "Nothing" }).click();
    await card.getByRole("button", { name: "Save" }).click();
    await expect.poll(() => saved.at(-1)).toEqual({ body_weight_kg: 72, display: "none" });
  });

  test("the first booking offers the calendar once; «Not now» is an answer (mockup e4 A)", async ({ page }) => {
    await stubApi(page);
    // The class is at 19:00 today: pin the browser clock to 06:00 so it is
    // still bookable whatever time the suite runs (it failed after 19:00).
    const now = new Date();
    now.setHours(6, 0, 0, 0);
    await page.clock.setFixedTime(now);
    const start = new Date(now);
    start.setHours(19, 0, 0, 0);
    const crossfit = { id: "ct-1", name: "CrossFit", kind: "class", levels: [], audiences: [] };
    await page.route("**/api/me/places**", (route) => route.fulfill(json({ places: [] })));
    await page.route("**/api/me/filters/box_schedule", (route) => route.fulfill(json({ surface: "box_schedule", last_used: null, saved: [] })));
    await page.route("**/api/org/*/schedule?**", (route) =>
      route.fulfill(
        json({
          start_date: localDate(),
          end_date: localDate(13),
          days: 14,
          class_types: [crossfit],
          coaches: [],
          slots: [
            {
              id: "s-1",
              name: "CrossFit",
              duration_minutes: 60,
              scheduled_at: start.toISOString(),
              class_type_id: crossfit.id,
              class_type: crossfit,
              capacity: 12,
              auto_approve: true,
              booking_timeout_minutes: 30,
              approved_booking_count: 4,
              spots_remaining: 8,
              coach_user_id: null,
              location_id: "loc-1",
              covered_by_package: true,
              workout: null,
              current_user_booking: null,
              bookings: [],
            },
          ],
        }),
      ),
    );
    await page.route("**/api/org/*/bookings", (route) =>
      route.fulfill(json({ booking: { id: "b-1", slot_id: "s-1", user_id: user.id, status: "approved" } }, 201)),
    );
    await page.route("**/api/calendar/export-links", (route) =>
      route.fulfill(json({ webcal_url: "webcal://palee.test/feed.ics?t=1", https_url: "https://palee.test/feed.ics?t=1" })),
    );

    await page.goto("/box/schedule");
    await page.getByRole("main").getByRole("button", { name: /CrossFit/ }).first().click();
    await page.getByRole("dialog", { name: "CrossFit" }).getByRole("button", { name: "Book" }).click();

    const offer = page.getByRole("dialog", { name: "Add your bookings to your calendar?" });
    await expect(offer).toBeVisible();
    await expect(offer.getByRole("link", { name: "Apple Calendar" })).toHaveAttribute("href", /^webcal:/);
    await offer.getByRole("button", { name: "Not now" }).click();
    await expect(offer).toHaveCount(0);
    expect(await page.evaluate(() => window.localStorage.getItem("palee:calendar-offer:member-1"))).toBe("no");
  });
});
