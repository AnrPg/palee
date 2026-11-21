import { expect, test, type Page } from "./support/test";

// ANR's pick A for the staff class page (2026-11-21): the class first, what
// waits for a decision, the WOD as the Deep hero card, «Participants» with
// «Here?» once the box's check-in window opens, and a bottom bar that follows
// the time. Two columns on a wide screen. The API is stubbed; every route not
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

  test("ten minutes before: «Start class» in Spark, and «Here?» records attendance", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    let recorded: { url: string; body: unknown } | null = null;
    await asOwner(page, classAt(inMinutes(10)));
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1/attendance/u-maria", (route) => {
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
    await expect(dialog.getByTestId("class-roster").getByTestId("class-arrived")).toHaveText("✓ Here");
    await expect(dialog.getByTestId("class-roster-count")).toHaveText("1 of 2 here");
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

  test("without a WOD: recent WODs one tap away and «Choose a WOD» in the bar", async ({ page }) => {
    let linked: unknown = null;
    await asOwner(page, classAt(inMinutes(180), { master_workout_id: null, workout: null, workout_status: "awaiting" }));
    await page.route("**/api/org/box1/admin/workouts/choices/suggested?**", (route) =>
      route.fulfill(json({ same_day: [], recent: [{ id: "w-legs", title: "Strength · Lower", type: "strength", icon: null }] })),
    );
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1/workout", (route) => {
      linked = JSON.parse(route.request().postData() ?? "{}");
      return route.fulfill(json({ slot: {} }));
    });
    await openClass(page);

    const card = page.getByTestId("class-wod-add");
    await expect(card).toContainText("No WOD yet");
    await expect(page.getByTestId("class-bar").getByRole("button", { name: "Choose a WOD" })).toBeVisible();
    await card.getByRole("button", { name: /Strength · Lower/ }).click();
    await expect.poll(() => linked).toEqual({ master_workout_id: "w-legs" });
  });

  test("on a wide screen the WOD and the people sit side by side", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await asOwner(page, classAt(inMinutes(180)));
    await openClass(page);

    const wod = await page.getByTestId("class-wod").boundingBox();
    const roster = await page.getByTestId("class-roster").boundingBox();
    expect(wod && roster).toBeTruthy();
    expect(roster!.x).toBeGreaterThan(wod!.x + wod!.width - 1);
    expect(Math.abs(roster!.y - wod!.y)).toBeLessThan(40);
  });
});
