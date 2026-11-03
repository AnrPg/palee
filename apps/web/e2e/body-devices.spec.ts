import { expect, test, type Page, type Request } from "./support/test";

// W9 body and devices (ADR-374..377, ontology §4.27): the watch row in
// Εγώ › Συνδεδεμένες συσκευές (mockup d8pair A), foods by barcode in the meal
// sheet (d9scan A, d9manual A), the rank ladders in Ρυθμίσεις › Προχωρημένα
// (e2setup A), the coach's promotion on a member's training tab (e2coach A)
// and «Οι βαθμοί μου» on Box (e2member A). The API is stubbed; every route
// not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

function tokenFor(sub: string, slug: string) {
  const payload = Buffer.from(JSON.stringify({ sub, role: "member", memberships: [{ organization_slug: slug }], exp: Math.floor(Date.now() / 1000) + 3600 })).toString(
    "base64url",
  );
  return `stub.${payload}.signature`;
}

async function asMember(page: Page) {
  const user = {
    id: "member-1",
    nickname: "Maria",
    role: "member",
    email: "member@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
  };
  const token = tokenFor(user.id, "kypseli");
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "member",
          roles: ["member"],
          capabilities: {},
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
}

async function asOwner(page: Page) {
  const user = {
    id: "owner-1",
    nickname: "Olga",
    role: "member",
    email: "owner@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role: "owner", settings: {} }],
  };
  const token = tokenFor(user.id, "box1");
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.addInitScript(() => {
    window.localStorage.setItem("palee:selected-organization-slug", "box1");
    window.localStorage.setItem("palee.view", "staff");
  });
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "owner",
          roles: ["owner"],
          capabilities: { manage_settings: "all", manage_memberships: "all" },
          organization: { id: "org-1", slug: "box1", name: "Box One", provider_kind: "gym", timezone: "UTC" },
          settings: { brand_name: "Box One", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

const rank = (id: string, name: string, color: string, position: number, requirements: Record<string, unknown> = {}) => ({
  id,
  position,
  name,
  color,
  max_stripes: 4,
  requirements,
  scale_level_slug: null,
});

const ladder = {
  id: "ladder-1",
  name: "BJJ",
  discipline: "bjj_grappling",
  style: "belt",
  class_type_ids: [],
  ranks: [rank("r-white", "White", "white", 0), rank("r-blue", "Blue", "blue", 1, { min_classes: 80, min_days: 730, skills: ["Armbar"] })],
};

const standing = {
  ladder,
  current: { award_id: "award-1", rank: ladder.ranks[0], stripes: 4, awarded_on: "2025-03-01" },
  next: ladder.ranks[1],
  progress: { rank_id: "r-blue", classes: { done: 80, needed: 80 }, days: { done: 760, needed: 730 }, skills: [], ready: true },
  history: [{ award_id: "award-1", rank: ladder.ranks[0], stripes: 4, awarded_on: "2025-03-01" }],
};

test.describe("body and devices", () => {
  test("the watch row opens its settings and a switch saves", async ({ page }) => {
    await asMember(page);
    await page.route("**/api/me/devices", (route) =>
      route.fulfill(
        json({
          wallet: { passes: [], platforms: { apple: false, google: false } },
          calendar: { https_url: "https://example.com/cal.ics", webcal_url: "webcal://example.com/cal.ics", download_url: null },
          integrations: [],
        }),
      ),
    );
    const watch = {
      platform: "apple_watch",
      device_name: "Maria's Apple Watch",
      contract_version: 1,
      needs_upgrade: false,
      settings: { show_heart_rate: true, show_pace: true, haptics: true, max_hr: null },
    };
    await page.route("**/api/me/devices/watches", (route) => route.fulfill(json({ watches: [watch] })));
    await page.route("**/api/me/devices/watches/apple_watch", (route) =>
      route.fulfill(json({ watch: { ...watch, settings: { ...watch.settings, ...bodyOf(route.request()).settings } } })),
    );

    await page.goto("/me/devices");
    await page.getByTestId("watch-row").getByRole("button").click();
    const sheet = page.getByTestId("watch-settings");
    await expect(sheet).toContainText("Maria's Apple Watch");
    const saved = page.waitForRequest((request) => request.url().endsWith("/me/devices/watches/apple_watch") && request.method() === "PUT");
    await sheet.getByRole("switch", { name: "Vibrate at the end of a round" }).click();
    expect(bodyOf(await saved)).toEqual({ contract_version: 1, settings: { haptics: false } });
    await expect(sheet.getByText("Maximum heart rate (for zones)")).toHaveCount(0);
  });

  test("a barcode adds a food to the meal with a hand portion and never calories", async ({ page }) => {
    await asMember(page);
    await page.route("**/api/me/wellness?**", (route) =>
      route.fulfill(
        json({
          consented: true,
          preferences: { glass_ml: 250, water_goal_ml: 2000, sleep_goal_minutes: 450, hidden_items: [], item_order: ["meals"], water_reminder: false },
          entries: [],
          days: [],
          plans: [],
          cravings: [],
          week: { water_days_logged: 0, water_days_on_goal: 0, nights_logged: 0, nights_on_goal: 0, meal_days_logged: 0, cravings: 0 },
        }),
      ),
    );
    await page.route("**/api/me/foods/barcode/5201054017104", (route) =>
      route.fulfill(
        json({
          barcode: "5201054017104",
          status: "found",
          source: "open_food_facts",
          macros_visible: false,
          attribution: {
            source: "Open Food Facts",
            licence: "ODbL 1.0",
            licence_url: "https://opendatacommons.org/licenses/odbl/1-0/",
            images_licence: "CC BY-SA 3.0",
            url: "https://world.openfoodfacts.org/product/5201054017104",
          },
          food: { name: "Strained yogurt 2%", brand: null, barcode: "5201054017104", portion_hint: "protein", nutrients: null },
        }),
      ),
    );

    await page.goto("/journal/wellbeing");
    await page.getByRole("button", { name: "+ Snack" }).click();
    await page.getByRole("button", { name: "Scan barcode" }).click();
    await page.getByLabel("Can't read it? Type it").fill("5201054017104");
    await page.getByRole("button", { name: "Look up" }).click();
    await expect(page.getByTestId("barcode-found")).toContainText("Strained yogurt 2%");
    await expect(page.getByText("Source: Open Food Facts · ODbL 1.0")).toBeVisible();
    await expect(page.getByRole("button", { name: "1 palm of protein" })).toHaveAttribute("aria-pressed", "true");
    await page.getByRole("button", { name: "Add to meal" }).click();
    await expect(page.getByText(/kcal|calorie/i)).toHaveCount(0);
  });

  test("the owner starts a ladder from a template in Settings › Advanced", async ({ page }) => {
    await asOwner(page);
    const ladders: unknown[] = [];
    await page.route("**/api/org/box1/admin/rank-ladders", (route) => {
      if (route.request().method() === "POST") {
        ladders.push(ladder);
        return route.fulfill(json({ ladder }, 201));
      }
      return route.fulfill(json({ ladders, templates: [{ key: "bjj_adult", discipline: "bjj_grappling" }] }));
    });

    await page.goto("/admin/settings");
    // ADR-377: belts and levels sit under «Advanced» › Ranks.
    await page.getByTestId("advanced-settings").getByRole("button", { name: /Advanced/ }).click();
    await expect(page.getByTestId("advanced-group-ranks")).toBeVisible();
    const created = page.waitForRequest((request) => request.url().endsWith("/admin/rank-ladders") && request.method() === "POST");
    await page.getByRole("button", { name: "BJJ belts" }).click();
    expect(bodyOf(await created)).toMatchObject({ template: "bjj_adult", name: "BJJ belts" });
    await expect(page.getByLabel("Ladder name")).toHaveValue("BJJ");
  });

  test("the coach promotes from the member's training tab; «Ready» only informs", async ({ page }) => {
    await asOwner(page);
    await page.route("**/api/org/box1/admin/users/u-2", (route) =>
      route.fulfill(
        json({
          user: {
            identity: { id: "u-2", nickname: "Tolaras", avatar_url: null, role: "member", joined_at: "2026-01-10T00:00:00Z" },
            account_status: "active",
            membership: { roles: ["member"], coach_scope: "own" },
            available_sections: ["overview", "training"],
            attention: [],
            operational_links: {},
          },
        }),
      ),
    );
    await page.route("**/api/org/box1/staff/clients/u-2/ranks", (route) =>
      route.request().method() === "POST"
        ? route.fulfill(json({ award: { award_id: "award-2", rank: ladder.ranks[1], stripes: 0, awarded_on: "2026-11-03" } }, 201))
        : route.fulfill(json({ ladders: [standing] })),
    );

    await page.goto("/admin/users/u-2?tab=training");
    const ranks = page.getByTestId("client-ranks");
    await expect(ranks).toContainText("Meets the requirements. The coach decides.");
    await ranks.getByRole("button", { name: "Promote" }).click();
    const sheet = page.getByTestId("promote-sheet");
    await sheet.getByRole("button", { name: "Armbar" }).click();
    const awarded = page.waitForRequest((request) => request.url().endsWith("/staff/clients/u-2/ranks") && request.method() === "POST");
    await sheet.getByRole("button", { name: "Promote" }).last().click();
    expect(bodyOf(await awarded)).toMatchObject({ ladder_id: "ladder-1", rank_id: "r-blue", stripes: 0, skills_checked: ["Armbar"] });
  });

  test("the member sees their belt and what is left for the next rank on Box", async ({ page }) => {
    await asMember(page);
    await page.route("**/api/org/kypseli/me/ranks", (route) => route.fulfill(json({ ladders: [standing] })));

    await page.goto("/box");
    await expect(page.getByText("For Blue:")).toBeVisible();
    await expect(page.getByRole("button", { name: "Diploma (PDF)" })).toBeVisible();
  });
});
