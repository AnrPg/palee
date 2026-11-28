import { expect, test, type Page } from "./support/test";

// ANR's pick A for the staff class page (2026-11-21): the class first, what
// waits for a decision, the WOD as the Deep hero card, «Participants» with
// «Here?» once the box's check-in window opens, and a bottom bar that follows
// the time. One column on every screen. The API is stubbed; every route not
// listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const booking = (id: string, userId: string, nickname: string, status: string, extra: Record<string, unknown> = {}) => ({
  id,
  user_id: userId,
  user_nickname: nickname,
  status,
  inserted_at: "2026-11-01T10:00:00Z",
  ...extra,
});

const workout = {
  id: "w-push",
  title: "Push day",
  type: "strength",
  content: [],
  authoring_mode: "free_text",
  free_text_body: "Bench press 4x8\nDB shoulder press 3x12",
  sections: [],
};

function classAt(startsAt: Date, overrides: Record<string, unknown> = {}) {
  return {
    id: "slot-1",
    class_series_id: null,
    master_workout_id: "w-push",
    published: true,
    workout_status: "linked",
    name: "Bodybuilding",
    duration_minutes: 60,
    scheduled_at: startsAt.toISOString(),
    class_type_id: "ct",
    class_type: { id: "ct", name: "Bodybuilding", slug: "strength" },
    capacity: 6,
    auto_approve: false,
    booking_timeout_minutes: 120,
    approved_booking_count: 2,
    spots_remaining: 4,
    waitlist_count: 0,
    workout,
    coach_user_id: "owner-1",
    location_id: null,
    bookings: [
      booking("b-1", "u-maria", "Maria D.", "approved"),
      booking("b-2", "u-nikos", "Nikos K.", "approved"),
      booking("b-3", "u-eleni", "Eleni P.", "pending"),
    ],
    ...overrides,
  };
}

async function asOwner(page: Page, slot: Record<string, unknown>) {
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
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const token = `stub.${payload}.signature`;
  const membership = {
    role: "owner",
    roles: ["owner", "coach"],
    capabilities: { manage_schedule: "all", run_classes: "all" },
    organization: { id: "org-1", slug: "box1", name: "Box One", provider_kind: "gym", timezone: "UTC" },
    settings: { brand_name: "Box One", brand_logo_url: null, brand_primary_color: null },
  };

  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.addInitScript(() => {
    window.localStorage.setItem("palee:selected-organization-slug", "box1");
    window.localStorage.setItem("palee.view", "staff");
  });
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([membership])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/box1/schedule?**", (route) =>
    route.fulfill(
      json({
        class_types: [{ id: "ct", name: "Bodybuilding", archived_at: null }],
        locations: [],
        coaches: [{ id: "owner-1", nickname: "Olga", avatar_url: null }],
        slots: [slot],
      }),
    ),
  );
  await page.route("**/api/org/box1/staff/members", (route) =>
    route.fulfill(json({ staff: [{ user_id: "owner-1", nickname: "Olga", role: "owner", roles: ["owner", "coach"] }] })),
  );
  await page.route("**/api/org/box1/admin/locations", (route) => route.fulfill(json({ locations: [] })));
  // The box's check-in window: 15′ before the start.
  await page.route("**/api/org/box1/admin/check-in/settings", (route) =>
    route.fulfill(json({ settings: { window_before_minutes: 15, window_after_minutes: 15 } })),
  );
}

async function openClass(page: Page) {
  await page.goto("/admin/schedule");
  const card = page.getByRole("button", { name: /Bodybuilding/ }).first();
  await expect(card).toBeVisible();
  await card.click();
  await expect(page.getByRole("dialog", { name: "Bodybuilding" })).toBeVisible();
}

const inMinutes = (minutes: number) => new Date(Date.now() + minutes * 60_000);

test.describe("Staff class page", () => {
  test("before the class: requests first, the WOD, then the people; the bar edits the class or its WOD", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    // Three hours ahead: inside today's window in most zones, and outside the check-in window.
    await asOwner(page, classAt(inMinutes(180)));
    await openClass(page);

    const dialog = page.getByRole("dialog", { name: "Bodybuilding" });
    await expect(dialog.getByRole("heading", { level: 2 })).toHaveText("Bodybuilding");
    await expect(dialog.getByTestId("slot-coach")).toHaveText("Coach: Olga");
    await expect(dialog.getByTestId("class-settings")).toContainText("2/6");
    await expect(dialog.getByTestId("slot-approval-wait")).toHaveText("2 hours");

    // What waits for a decision comes before the WOD, and the WOD before the people.
    const pending = dialog.getByTestId("class-pending");
    await expect(pending).toContainText("1 booking request is waiting");
    await expect(pending).toContainText("Eleni P.");
    await expect(pending.getByRole("button", { name: "Approve" })).toBeVisible();
    const order = await dialog.evaluate((root) =>
      ["class-pending", "class-wod", "class-roster"].map(
        (id) => root.querySelector(`[data-testid=${id}]`)!.getBoundingClientRect().top,
      ),
    );
    expect(order[0]).toBeLessThan(order[1]);
    expect(order[1]).toBeLessThan(order[2]);

    // The WOD shows its whole content; the people have no «Here?» yet.
    await expect(dialog.getByTestId("class-wod")).toContainText("Push day");
    await expect(dialog.getByTestId("class-wod")).toContainText("Bench press 4x8");
    const roster = dialog.getByTestId("class-roster");
    await expect(roster).toContainText("Maria D.");
    await expect(roster).not.toContainText("Eleni P.");
    await expect(roster.getByRole("button", { name: /as here/ })).toHaveCount(0);

    // The bar opens the same menus as the ⋯ at the top and on the WOD.
    const bar = dialog.getByTestId("class-bar");
    await expect(bar).toBeInViewport();
    await bar.getByRole("button", { name: "Edit class" }).click();
    await expect(page.getByRole("menuitem", { name: "Edit class" })).toBeVisible();
    await page.keyboard.press("Escape");
    await bar.getByRole("button", { name: "Edit WOD" }).click();
    await expect(page.getByRole("menuitem", { name: "Change WOD" })).toBeVisible();
    await page.keyboard.press("Escape");
  });

  test("the settings line opens the class's settings with «Edit class»", async ({ page }) => {
    await asOwner(page, classAt(inMinutes(180)));
    await openClass(page);

    await page.getByTestId("class-settings").click();
    const sheet = page.getByRole("dialog", { name: "Class settings" });
    await expect(sheet).toContainText("Manual");
    await expect(sheet).toContainText("2 of 6");
    await sheet.getByRole("button", { name: "Edit class" }).click();
    await expect(page.getByRole("dialog", { name: "Edit scheduled class" })).toBeVisible();
  });

  test("ten minutes before: «Start class» in Spark, «Here?» records attendance and «✓ Here» takes it back", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    let recorded: { url: string; body: unknown } | null = null;
    let removed = 0;
    await asOwner(page, classAt(inMinutes(10)));
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1/attendance/u-maria", (route) => {
      if (route.request().method() === "DELETE") {
        removed += 1;
        return route.fulfill({ status: 204, body: "" });
      }
      recorded = { url: route.request().url(), body: JSON.parse(route.request().postData() ?? "{}") };
      return route.fulfill(json({ attendance: { status: "attended" } }));
    });
    await openClass(page);

    const dialog = page.getByRole("dialog", { name: "Bodybuilding" });
    await expect(dialog.getByTestId("class-phase")).toHaveText(/^In \d+′$/);
    const start = dialog.getByTestId("class-bar-start");
    await expect(start).toHaveText(/Start class/);
    await expect(start).toHaveAttribute("href", /\/class-timer\/slot-1\/control$/);

    const mark = dialog.getByRole("button", { name: "Mark Maria D. as here" });
    await expect(mark).toBeVisible();
    await expect(mark).toBeEnabled();
    await mark.click();
    await expect.poll(() => recorded?.body).toEqual({ status: "attended" });
    const here = dialog.getByTestId("class-roster").getByTestId("class-arrived");
    await expect(here).toHaveText("✓ Here");
    await expect(dialog.getByTestId("class-roster-count")).toHaveText("1 of 2 here");

    // A wrong tap: «✓ Here» takes it back and «Here?» returns.
    const undo = dialog.getByRole("button", { name: "Take back «Here» for Maria D." });
    await expect(undo).toBeVisible();
    await expect(undo).toBeEnabled();
    await undo.click();
    await expect.poll(() => removed).toBe(1);
    await expect(dialog.getByRole("button", { name: "Mark Maria D. as here" })).toBeVisible();
    await expect(dialog.getByTestId("class-roster-count")).toHaveText("0 of 2 here");
  });

  test("a member who checked in themselves shows as here without a tap", async ({ page }) => {
    await asOwner(
      page,
      classAt(inMinutes(-10), {
        bookings: [booking("b-1", "u-maria", "Maria D.", "approved", { attendance_status: "attended" }), booking("b-2", "u-nikos", "Nikos K.", "approved")],
      }),
    );
    await openClass(page);

    const roster = page.getByTestId("class-roster");
    await expect(roster.getByTestId("class-arrived")).toHaveText("✓ Here");
    await expect(roster.getByRole("button", { name: "Mark Nikos K. as here" })).toBeVisible();
    await expect(page.getByTestId("class-phase")).toHaveText("Now");
  });

  test("without a WOD: another class's WOD that day one tap away, never recent ones, and «Choose a WOD» in the bar", async ({ page }) => {
    let linked: unknown = null;
    await asOwner(page, classAt(inMinutes(180), { master_workout_id: null, workout: null, workout_status: "awaiting" }));
    await page.route("**/api/org/box1/admin/workouts/choices/suggested?**", (route) =>
      route.fulfill(
        json({
          same_day: [{ id: "w-legs", title: "Strength · Lower", type: "strength", icon: null }],
          recent: [{ id: "w-engine", title: "Hybrid · Engine", type: "hybrid", icon: null }],
        }),
      ),
    );
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1/workout", (route) => {
      linked = JSON.parse(route.request().postData() ?? "{}");
      return route.fulfill(json({ slot: {} }));
    });
    await openClass(page);

    const card = page.getByTestId("class-wod-add");
    await expect(card).toContainText("No WOD yet");
    await expect(page.getByTestId("class-bar").getByRole("button", { name: "Choose a WOD" })).toBeVisible();
    await expect(card.getByRole("button", { name: /Strength · Lower/ })).toBeVisible();
    await expect(card).not.toContainText("Hybrid · Engine");
    await card.getByRole("button", { name: /Strength · Lower/ }).click();
    await expect.poll(() => linked).toEqual({ master_workout_id: "w-legs" });
  });

  test("on a wide screen it stays one column in a drawer about as wide as a phone", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await asOwner(page, classAt(inMinutes(180)));
    await openClass(page);

    const drawer = await page.getByRole("dialog", { name: "Bodybuilding" }).boundingBox();
    const wod = await page.getByTestId("class-wod").boundingBox();
    const roster = await page.getByTestId("class-roster").boundingBox();
    expect(drawer && wod && roster).toBeTruthy();
    expect(drawer!.width).toBeLessThanOrEqual(520);
    expect(roster!.y).toBeGreaterThan(wod!.y + wod!.height - 1);
    expect(Math.abs(roster!.x - wod!.x)).toBeLessThan(2);
  });

  test("ADR-746: two WODs in one class: chips with «Now», another WOD in full, «Make it «Now»» and the people by WOD", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    let live: unknown = null;
    const legs = { ...workout, id: "w-legs", title: "Leg day", free_text_body: "Back squat 5x5" };
    await asOwner(
      page,
      classAt(inMinutes(180), {
        workouts: [workout, legs],
        live_workout_id: "w-push",
        bookings: [
          booking("b-1", "u-maria", "Maria D.", "approved", { chosen_workout_id: "w-legs" }),
          booking("b-2", "u-nikos", "Nikos K.", "approved", { chosen_workout_id: null }),
        ],
      }),
    );
    await page.route("**/api/org/box1/class-timers/slot-1", (route) =>
      route.fulfill(json({ timer: { status: "ready", lock_version: 1 }, workout: { id: "w-push" }, live: true })),
    );
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1/live-workout", (route) => {
      live = JSON.parse(route.request().postData() ?? "{}");
      return route.fulfill(json({ slot: {} }));
    });
    await openClass(page);

    const dialog = page.getByRole("dialog", { name: "Bodybuilding" });
    const chips = dialog.getByTestId("class-wod-chip");
    await expect(chips).toHaveCount(2);
    await expect(chips.first()).toContainText("Push day");
    await expect(chips.first().getByTestId("class-wod-live")).toHaveText("Now");
    await expect(dialog.getByTestId("class-wod-add-more")).toHaveText("+ WOD");

    // Another WOD opens in full; «Now» stays where it is.
    await expect(chips.nth(1)).toBeVisible();
    await chips.nth(1).click();
    await expect(chips.nth(1)).toHaveAttribute("aria-pressed", "true");
    await expect(dialog.getByTestId("class-wod")).toContainText("Back squat 5x5");

    // The people come by WOD, then those who decide at the box.
    const groups = dialog.getByTestId("class-roster-wod-group");
    // A WOD nobody does yet has no group of its own.
    await expect(groups).toHaveCount(2);
    await expect(groups.nth(0)).toContainText("Leg day");
    await expect(groups.nth(0)).toContainText("Maria D.");
    await expect(groups.nth(1)).toContainText("Deciding at the box");
    await expect(groups.nth(1)).toContainText("Nikos K.");

    // «Make it «Now»» from the WOD's menu: nothing runs, so no question.
    const menu = dialog.getByTestId("workout-more-actions");
    await expect(menu).toBeVisible();
    await menu.click();
    const makeLive = page.getByRole("menuitem", { name: "Make it «Now»" });
    await expect(makeLive).toBeVisible();
    await makeLive.click();
    await expect.poll(() => live).toEqual({ workout_id: "w-legs" });
  });

  test("«+ Add» puts a member on a full class's waitlist, first in line (ADR-790)", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    const full = classAt(inMinutes(180), {
      capacity: 2,
      approved_booking_count: 2,
      spots_remaining: 0,
      waitlist_count: 1,
      bookings: [
        booking("b-1", "u-maria", "Maria D.", "approved"),
        booking("b-2", "u-nikos", "Nikos K.", "approved"),
        booking("b-4", "u-sofia", "Sofia L.", "waitlisted", { waitlist_position: 1 }),
      ],
    });
    await asOwner(page, full);
    const entries: unknown[] = [];
    await page.route("**/api/org/box1/admin/athletes?**", (route) =>
      route.fulfill(
        json({
          athletes: [
            { id: "u-maria", nickname: "Maria D.", role: "member" },
            { id: "u-dimitra", nickname: "Dimitra A.", role: "member" },
            { id: "u-coachee", nickname: "Dina Online", role: "athlete" },
          ],
        }),
      ),
    );
    await page.route("**/api/org/box1/admin/users/u-dimitra/class-placement?**", (route) =>
      route.fulfill(
        json({
          timezone: "UTC",
          lookahead_days: 30,
          bookings: [],
          classes: [
            {
              slot_id: "slot-1",
              name: "Bodybuilding",
              scheduled_at: full.scheduled_at,
              duration_minutes: 60,
              capacity: 2,
              spots_remaining: 0,
              blocked_reason: null,
              waitlist: true,
              waitlist_place: 2,
            },
          ],
        }),
      ),
    );
    await page.route("**/api/org/box1/admin/users/u-dimitra/class-waitlist", (route) => {
      entries.push(JSON.parse(route.request().postData() ?? "{}"));
      return route.fulfill(json({ booking: { id: "b-5", status: "waitlisted" }, waitlist_position: 1 }, 201));
    });
    await openClass(page);

    const dialog = page.getByRole("dialog", { name: "Bodybuilding" });
    const add = dialog.getByTestId("class-roster-add");
    await add.scrollIntoViewIfNeeded();
    await expect(add).toBeVisible();
    await add.click();

    const sheet = page.getByTestId("add-to-class-dialog");
    await expect(sheet).toBeVisible();
    await sheet.getByTestId("add-to-class-search").fill("D");
    // Only members not in the class yet.
    await expect(sheet.getByRole("button", { name: "Dimitra A." })).toBeVisible();
    await expect(sheet.getByRole("button", { name: "Maria D." })).toHaveCount(0);
    await expect(sheet.getByRole("button", { name: "Dina Online" })).toHaveCount(0);
    await sheet.getByRole("button", { name: "Dimitra A." }).click();

    const position = sheet.getByTestId("waitlist-position");
    await expect(position.getByRole("radio", { name: "At the end (place 2)" })).toBeChecked();
    await position.getByRole("radio", { name: "First in line" }).check();
    const confirm = sheet.getByTestId("add-to-class-confirm");
    await expect(confirm).toHaveText("Add to waitlist");
    await expect(confirm).toBeEnabled();
    await confirm.click();
    await expect.poll(() => entries).toEqual([{ slot_id: "slot-1", position: "first" }]);
    await expect(sheet).toBeHidden();
  });
});

