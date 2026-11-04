import { expect, test, type Page, type Request } from "./support/test";

// W9 body and devices (ADR-374..377, ontology §4.27): the watch row in
// Εγώ › Συνδεδεμένες συσκευές (mockup d8pair A), foods by barcode in the meal
// sheet (d9scan A, d9manual A; «Φωτογραφία ετικέτας», ADR-421), the rank ladders in Ρυθμίσεις › Προχωρημένα
// (template picker Β, curriculum editor Α), the coach's ticks and promotion on a
// member's training tab (ticking Α and Γ) and «Η πρόοδός μου» from Box (Γ line,
// Α page). The API is stubbed; every route
// not listed answers an empty object.

// A 1×1 PNG for the label photo.
const PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=";

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
  ready_criteria: ["classes", "days"],
  ranks: [
    rank("r-white", "White", "white", 0),
    rank("r-blue", "Blue", "blue", 1, { min_classes: 80, min_days: 730, skills: ["Armbar", "Triangle"], skill_ids: ["s-armbar", "s-triangle"], skill_notes: [null, "Knees tight"] }),
  ],
};

const standing = {
  ladder,
  current: { award_id: "award-1", rank: ladder.ranks[0], stripes: 4, awarded_on: "2025-03-01" },
  next: ladder.ranks[1],
  progress: {
    rank_id: "r-blue",
    classes: { done: 80, needed: 80 },
    days: { done: 760, needed: 730 },
    skills: ["Armbar", "Triangle"],
    skills_checked: [{ skill: "Armbar", skill_id: "s-armbar", checked_on: "2026-10-12", note: null }],
    ready: true,
  },
  history: [{ id: "award-1", ladder_id: "ladder-1", rank_id: "r-white", rank_name: ladder.ranks[0].name, color: "white", stripes: 4, awarded_on: "2025-03-01", certificate_number: "PAL-2025-0001", revoked: false }],
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
          photos: {},
          photo_capabilities: { content_types: ["image/jpeg", "image/png", "image/webp"], max_bytes: 10_000_000 },
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

  test("a barcode nobody has becomes «Δικό μου τρόφιμο», prefilled from a photo of the label", async ({ page }) => {
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
          photos: {},
          photo_capabilities: { content_types: ["image/jpeg", "image/png", "image/webp"], max_bytes: 10_000_000 },
          week: { water_days_logged: 0, water_days_on_goal: 0, nights_logged: 0, nights_on_goal: 0, meal_days_logged: 0, cravings: 0 },
        }),
      ),
    );
    await page.route("**/api/me/foods/barcode/5201234500006", (route) =>
      route.fulfill(json({ barcode: "5201234500006", status: "manual", reason: "not_found", macros_visible: false, label_reading: true, food: null })),
    );
    let labelRequest: Request | null = null;
    await page.route("**/api/me/foods/label-read", (route) => {
      labelRequest = route.request();
      return route.fulfill(
        json({ macros_visible: false, food: { name: "Feta PDO", brand: "Sandbox Dairy", serving_label: "30 g", portion_hint: "fat", nutrients: null } }),
      );
    });
    let saved: Record<string, unknown> | null = null;
    await page.route("**/api/me/foods", (route) => {
      if (route.request().method() !== "POST") return route.fulfill(json({ foods: [], macros_visible: false }));
      saved = bodyOf(route.request());
      return route.fulfill(json({ food: { id: "food-1", name: "Feta PDO", portion_hint: "fat", nutrients: null } }, 201));
    });

    await page.goto("/journal/wellbeing");
    await page.getByRole("button", { name: "+ Snack" }).click();
    await page.getByRole("button", { name: "Scan barcode" }).click();
    await page.getByLabel("Can't read it? Type it").fill("5201234500006");
    await page.getByRole("button", { name: "Look up" }).click();
    await expect(page.getByTestId("own-food")).toContainText("We didn't find it");
    await page.getByRole("button", { name: "Photo of the label" }).click();
    await page.getByLabel("Front of the pack").setInputFiles({ name: "front.png", mimeType: "image/png", buffer: Buffer.from(PNG, "base64") });
    await page.getByRole("button", { name: "Read the label" }).click();
    await expect(page.getByLabel("What it is")).toHaveValue("Feta PDO");
    expect(labelRequest).not.toBeNull();
    expect(labelRequest!.headers()["content-type"]).toContain("multipart/form-data");
    await expect(page.getByRole("textbox", { name: "Brand" })).toHaveValue("Sandbox Dairy");
    await expect(page.getByRole("button", { name: "1 thumb of fat" })).toHaveAttribute("aria-pressed", "true");
    await expect(page.getByTestId("own-food-nutrients")).toHaveCount(0);
    // ADR-421 addendum: sharing is an explicit choice, never ticked for the person.
    await expect(page.getByLabel("Share it with everyone on Palee and on Open Food Facts")).not.toBeChecked();
    await page.getByRole("button", { name: "Save food" }).click();
    await expect.poll(() => saved).toEqual({ name: "Feta PDO", barcode: "5201234500006", brand: "Sandbox Dairy", serving_label: "30 g", portion_hint: "fat" });
    await expect(page.getByText(/kcal|calorie/i)).toHaveCount(0);
  });

  test("«Μοιράσου το» shares a barcoded own food only when ticked; a shared product shows «από μέλη»", async ({ page }) => {
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
          photos: {},
          photo_capabilities: { content_types: ["image/jpeg", "image/png", "image/webp"], max_bytes: 10_000_000 },
          week: { water_days_logged: 0, water_days_on_goal: 0, nights_logged: 0, nights_on_goal: 0, meal_days_logged: 0, cravings: 0 },
        }),
      ),
    );
    await page.route("**/api/me/foods/barcode/5201234500006", (route) =>
      route.fulfill(json({ barcode: "5201234500006", status: "manual", reason: "not_found", macros_visible: false, label_reading: false, food: null })),
    );
    await page.route("**/api/me/foods/barcode/2001234000000", (route) =>
      route.fulfill(json({ barcode: "2001234000000", status: "manual", reason: "in_store_code", macros_visible: false, label_reading: false, food: null })),
    );
    await page.route("**/api/me/foods/barcode/5201234500013", (route) =>
      route.fulfill(
        json({
          barcode: "5201234500013",
          status: "found",
          source: "palee_members",
          macros_visible: false,
          attribution: { source: "Palee members", licence: "ODbL-1.0", licence_url: "https://opendatacommons.org/licenses/odbl/1-0/", images_licence: null, url: null },
          food: { id: null, name: "Rusks", brand: "Bakery", barcode: "5201234500013", portion_hint: "carbs", nutrients: null },
        }),
      ),
    );
    let saved: Record<string, unknown> | null = null;
    await page.route("**/api/me/foods", (route) => {
      if (route.request().method() !== "POST") return route.fulfill(json({ foods: [], macros_visible: false }));
      saved = bodyOf(route.request());
      return route.fulfill(
        json({ food: { id: "food-2", name: "Rusks", portion_hint: null, nutrients: null, shared_at: "2026-11-03T10:00:00Z" } }, 201),
      );
    });

    await page.goto("/journal/wellbeing");
    await page.getByRole("button", { name: "+ Snack" }).click();

    // A shop's own code is no product: nothing to share.
    await page.getByRole("button", { name: "Scan barcode" }).click();
    await page.getByLabel("Can't read it? Type it").fill("2001234000000");
    await page.getByRole("button", { name: "Look up" }).click();
    await expect(page.getByTestId("own-food")).toBeVisible();
    await expect(page.getByTestId("own-food-share")).toHaveCount(0);
    await page.getByTestId("own-food").getByRole("button", { name: "Cancel" }).click();

    await page.getByRole("button", { name: "Scan barcode" }).click();
    await page.getByLabel("Can't read it? Type it").fill("5201234500006");
    await page.getByRole("button", { name: "Look up" }).click();
    const share = page.getByLabel("Share it with everyone on Palee and on Open Food Facts");
    await expect(share).not.toBeChecked();
    await expect(page.getByText("Only the barcode, name, brand, portion and nutrition per 100 g are shared.", { exact: false })).toBeVisible();
    await page.getByLabel("What it is").fill("Rusks");
    await share.check();
    await page.getByRole("button", { name: "Save food" }).click();
    await expect.poll(() => saved).toEqual({ name: "Rusks", barcode: "5201234500006", share: true });

    await page.getByRole("button", { name: "Scan barcode" }).click();
    await page.getByLabel("Can't read it? Type it").fill("5201234500013");
    await page.getByRole("button", { name: "Look up" }).click();
    await expect(page.getByTestId("from-members")).toHaveText("from members");
    await expect(page.getByText("Source: Palee members · ODbL-1.0")).toBeVisible();
  });

  test("the owner starts a ladder from a template in Settings › Advanced (picker, option Β)", async ({ page }) => {
    await asOwner(page);
    const ladders: unknown[] = [];
    // ADR-400: the catalogue comes from the server in the page's language (`?locale=`).
    await page.route(/\/api\/org\/box1\/admin\/rank-ladders(\?.*)?$/, (route) => {
      if (route.request().method() === "POST") {
        ladders.push(ladder);
        return route.fulfill(json({ ladder }, 201));
      }
      return route.fulfill(
        json({
          ladders,
          box_disciplines: ["judo"],
          templates: [
            { key: "bjj_adult", name: "BJJ belts", discipline: "bjj_grappling", style: "belt", source: "federation", system: "IBJJF", ranks: [{ name: "White", color: "white" }] },
            { key: "bjj_kids", name: "BJJ kids", discipline: "bjj_grappling", style: "belt", source: "federation", ranks: [] },
            { key: "judo_kyu", name: "Judo belts", discipline: "judo", style: "belt", source: "federation", ranks: [] },
            "not a template",
          ],
        }),
      );
    });

    await page.goto("/admin/settings");
    // ADR-377: belts and levels sit under «Advanced» › Ranks.
    await page.getByTestId("advanced-settings").getByRole("button", { name: /Advanced/ }).click();
    await expect(page.getByTestId("advanced-group-ranks")).toBeVisible();
    const picker = page.getByTestId("rank-template-picker");
    // Step 1: the box's own kinds first, each with its template count.
    await expect(picker.getByTestId("rank-kinds-mine")).toContainText("Judo");
    await picker.getByTestId("rank-kinds").getByRole("button", { name: /BJJ/ }).click();
    await expect(picker.getByRole("button", { name: "Continue" })).toBeDisabled();
    // Step 2: that kind's templates with their source and system.
    const adult = picker.getByRole("radio", { name: /BJJ belts/ });
    await expect(adult).toContainText("Official system");
    await expect(adult).toContainText("IBJJF");
    await adult.click();
    const created = page.waitForRequest((request) => request.url().endsWith("/admin/rank-ladders") && request.method() === "POST");
    await picker.getByRole("button", { name: "Continue" }).click();
    expect(bodyOf(await created)).toMatchObject({ template: "bjj_adult", name: "BJJ belts", locale: "en" });
    await expect(page.getByLabel("Ladder name")).toHaveValue("BJJ");
  });

  test("the owner edits a rank's skills one per row and saves with the save bar (editor, option Α)", async ({ page }) => {
    await asOwner(page);
    let saved: Record<string, unknown> | null = null;
    await page.route(/\/api\/org\/box1\/admin\/rank-ladders(\?.*)?$/, (route) => route.fulfill(json({ ladders: [ladder], templates: [], box_disciplines: [] })));
    await page.route("**/api/org/box1/admin/rank-ladders/ladder-1", (route) => {
      saved = bodyOf(route.request());
      return route.fulfill(json({ ladder }));
    });

    await page.goto("/admin/settings");
    await page.getByTestId("advanced-settings").getByRole("button", { name: /Advanced/ }).click();
    const editor = page.getByTestId("rank-ladder-ladder-1");
    await editor.getByTestId("rank-section").filter({ hasText: "Blue" }).getByRole("button", { name: /Blue/ }).first().click();
    const skills = editor.getByTestId("rank-skills");
    await expect(skills.getByRole("textbox", { name: "Skill" })).toHaveCount(2);
    await skills.getByRole("textbox", { name: "Skill" }).first().fill("Armbar from guard");
    await skills.getByRole("button", { name: "Remove: Triangle" }).click();
    await editor.getByRole("button", { name: "Add skill" }).click();
    await skills.getByRole("textbox", { name: "Skill" }).last().fill("Kimura");
    await page.getByTestId("rank-ladder-save-ladder-1").getByRole("button", { name: "Save" }).click();
    await expect.poll(() => (saved as { ranks?: { requirements: unknown }[] } | null)?.ranks?.[1]?.requirements).toEqual({
      min_days: 730,
      min_classes: 80,
      skills: ["Armbar from guard", "Kimura"],
      skill_ids: ["s-armbar", null],
    });
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
    let ticked: Record<string, unknown> | null = null;
    await page.route("**/api/org/box1/staff/clients/u-2/ranks", (route) =>
      route.request().method() === "POST"
        ? route.fulfill(json({ award: { award_id: "award-2", rank: ladder.ranks[1], stripes: 0, awarded_on: "2026-11-03" } }, 201))
        : route.fulfill(json({ ladders: [standing] })),
    );
    await page.route("**/api/org/box1/staff/clients/u-2/ranks/skills", (route) => {
      ticked = bodyOf(route.request());
      return route.fulfill(json({ ladders: [standing] }));
    });

    await page.goto("/admin/users/u-2?tab=training");
    const ranks = page.getByTestId("client-ranks");
    await expect(ranks).toContainText("Meets the requirements. The coach decides.");
    // Option Α: one tap ticks a skill on the profile.
    const checklist = ranks.getByTestId("skill-checklist");
    await expect(checklist).toContainText("1 of 2 skills");
    await checklist.getByRole("button", { name: "Triangle", exact: true }).click();
    await expect.poll(() => ticked).toEqual({ rank_id: "r-blue", skill_id: "s-triangle", checked: true });

    // Option Γ: the promotion comes pre-filled with what is ticked.
    await ranks.getByRole("button", { name: "Promote" }).click();
    const sheet = page.getByTestId("promote-sheet");
    await sheet.getByRole("button", { name: /Blue/ }).click();
    await expect(sheet.getByRole("button", { name: /Armbar/ })).toHaveAttribute("aria-pressed", "true");
    const awarded = page.waitForRequest((request) => request.url().endsWith("/staff/clients/u-2/ranks") && request.method() === "POST");
    await sheet.getByRole("button", { name: "Promote" }).last().click();
    expect(bodyOf(await awarded)).toMatchObject({ ladder_id: "ladder-1", rank_id: "r-blue", stripes: 0, skills_checked: ["Armbar"] });
  });

  test("the member sees one line on the profile and opens their progress page", async ({ page }) => {
    await asMember(page);
    await page.route("**/api/org/kypseli/me/ranks", (route) => route.fulfill(json({ ladders: [standing] })));

    await page.goto("/me");
    const line = page.getByTestId("my-ranks-open");
    await expect(line).toContainText("White");
    await expect(line).toContainText("towards Blue: 1 of 2 skills");
    await line.click();
    await expect(page).toHaveURL(/\/me\/ranks$/);
    const card = page.getByTestId("next-rank-card");
    await expect(card).toContainText("Still to learn");
    // One requirement per line (days, classes, skills), never joined with «·».
    await expect(page.getByTestId("next-rank-counts").getByRole("listitem")).toHaveCount(3);
    await expect(card).toContainText("Triangle");
    await card.getByText("Note").click();
    await expect(card).toContainText("Knees tight");
    await expect(page.getByTestId("my-ranks-path")).toContainText("Blue");
    await expect(page.getByRole("button", { name: "Diploma (PDF)" })).toBeVisible();
  });
});
