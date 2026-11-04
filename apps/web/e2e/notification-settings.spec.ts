import { expect, test, type Locator, type Page } from "./support/test";

// ADR-199: Εγώ › Ρυθμίσεις › Ειδοποιήσεις. One row per category with a
// switch per channel, account and payments locked on, the staff row only for
// staff, and a bell notification that opens a section of Settings. The API
// is stubbed.

const user = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "member", settings: {} }],
};

function token() {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown) => ({ status: 200, contentType: "application/json", body: JSON.stringify(body) });

const CATEGORIES = ["bookings", "messages", "community", "coach", "partners", "journal", "staff", "account"] as const;

type Row = { category: string; locked: boolean; audience: string; channels: { in_app: boolean; push: boolean } };

async function stub(page: Page, { staff = false, notifications = [] as unknown[] } = {}) {
  const rows: Row[] = CATEGORIES.map((category) => ({
    category,
    locked: category === "account",
    audience: category === "staff" ? "staff" : "everyone",
    channels: { in_app: true, push: true },
  }));
  const updates: { category: string; body: Record<string, boolean> }[] = [];
  const role = staff ? "coach" : "member";

  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(json([{ role, roles: [role], status: "active", organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" }, settings: {} }])),
  );
  await page.route("**/api/notifications?**", (route) =>
    route.fulfill(json({ notifications, next_cursor: null, unread_count: notifications.length })),
  );
  // The bell's badge reads the count alone; the list loads when the panel opens.
  await page.route("**/api/notifications/unread-count", (route) => route.fulfill(json({ unread_count: notifications.length })));
  await page.route("**/api/notifications/preferences", (route) => route.fulfill(json({ preferences: rows })));
  await page.route("**/api/notifications/preferences/*", (route) => {
    const category = route.request().url().split("/").pop()!;
    const body = route.request().postDataJSON() as Record<string, boolean>;
    updates.push({ category, body });
    const row = rows.find((r) => r.category === category)!;
    row.channels = { ...row.channels, ...body };
    if (!row.channels.in_app) row.channels.push = false;
    return route.fulfill(json({ preferences: rows }));
  });
  return updates;
}

/** A one-finger swipe to the left across the element, as touch events (Chromium). */
async function swipeLeft(page: Page, target: Locator) {
  const box = (await target.boundingBox())!;
  const y = box.y + box.height / 2;
  const from = box.x + box.width - 24;
  const cdp = await page.context().newCDPSession(page);
  const touch = (type: "touchStart" | "touchMove" | "touchEnd", x: number) =>
    cdp.send("Input.dispatchTouchEvent", { type, touchPoints: type === "touchEnd" ? [] : [{ x, y }] });
  await touch("touchStart", from);
  for (let step = 1; step <= 8; step += 1) await touch("touchMove", from - step * 20);
  await touch("touchEnd", from - 160);
  await cdp.detach();
}

test.describe("notification settings", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("a member switches categories per channel; account stays locked, staff row hidden", async ({ page }) => {
    const updates = await stub(page);
    await page.goto("/me/settings#notifications");

    const section = page.locator("section#notifications");
    await expect(section.getByText("Notifications", { exact: true })).toBeVisible();
    const list = section.getByTestId("notification-categories");
    await expect(list.locator("[data-category]")).toHaveCount(7);
    await expect(list.locator('[data-category="staff"]')).toHaveCount(0);
    await expect(list.locator('[data-category="account"]')).toContainText("Always on");
    await expect(list.locator('[data-category="account"]').getByRole("switch")).toHaveCount(0);
    await expect(list.locator('[data-category="community"]').getByRole("link", { name: /Per club/ })).toHaveAttribute("href", "/me/clubs");

    const communityPush = list.getByRole("switch", { name: "Clubs & community · Push" });
    await expect(communityPush).toHaveAttribute("aria-checked", "true");
    await communityPush.click();
    await expect(communityPush).toHaveAttribute("aria-checked", "false");
    expect(updates).toContainEqual({ category: "community", body: { push: false } });

    // Push is made from the bell's notification: with the bell off, push is off and locked.
    await list.getByRole("switch", { name: "Journal reminders · In app" }).click();
    const journalPush = list.getByRole("switch", { name: "Journal reminders · Push" });
    await expect(journalPush).toHaveAttribute("aria-checked", "false");
    await expect(journalPush).toBeDisabled();
    expect(updates).toContainEqual({ category: "journal", body: { in_app: false } });

    // ANR 2026-11-04: each column is explained, and its head stays over its switches.
    await expect(section.getByTestId("notification-channel-help")).toContainText("even when Palee is closed");
    const heads = section.getByTestId("notification-channel-heads").locator("span");
    const pushHead = (await heads.nth(1).boundingBox())!;
    const pushSwitch = (await communityPush.boundingBox())!;
    expect(Math.abs(pushHead.x + pushHead.width / 2 - (pushSwitch.x + pushSwitch.width / 2))).toBeLessThan(2);
    for (const head of await heads.all()) {
      const box = (await head.boundingBox())!;
      expect(box.width).toBeLessThanOrEqual(64.5);
    }

    // No horizontal scroll at phone width.
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow).toBeLessThanOrEqual(0);
  });

  test("staff also see the box-operations row", async ({ page }) => {
    await stub(page, { staff: true });
    await page.goto("/me/settings#notifications");
    await expect(page.locator('section#notifications [data-category="staff"]')).toContainText("Running the box");
  });

  test("a bell notification opens its section of Settings", async ({ page }) => {
    await stub(page, {
      notifications: [
        {
          id: "n-1",
          user_id: user.id,
          organization_id: null,
          type: "password_reset_completed",
          payload: { url: "/me/settings#security" },
          read_at: null,
          inserted_at: new Date().toISOString(),
        },
      ],
    });
    await page.goto("/me/settings");
    await page.getByTestId("member-top-bar").getByRole("button", { name: "1 unread notification" }).click();
    await page.getByRole("dialog", { name: "Notifications" }).getByText("Your password was reset").click();

    await expect(page).toHaveURL(/\/me\/settings#security$/);
    await expect(page.getByRole("button", { name: "Sign out all devices" })).toBeVisible();
  });

  // Beta box 2026-11-02: 51 notifications on the badge, «temporarily
  // unavailable» in the panel (the API failed on any inbox longer than one
  // page). The panel offers a retry and pages through a long inbox.
  test("the bell retries a failed inbox and pages through a long one", async ({ page }) => {
    await stub(page);
    const note = (index: number) => ({
      id: `n-${index}`,
      user_id: user.id,
      organization_id: null,
      type: "password_reset_completed",
      payload: { url: "/me/settings#security" },
      read_at: null,
      inserted_at: new Date(Date.now() - index * 60_000).toISOString(),
    });
    // The app retries a failed read once by itself, so fail both.
    let failures = 2;
    const cursors: (string | null)[] = [];
    await page.route("**/api/notifications/unread-count", (route) => route.fulfill(json({ unread_count: 25 })));
    await page.route("**/api/notifications?**", (route) => {
      if (failures-- > 0) return route.fulfill({ status: 500, contentType: "application/json", body: "{}" });
      const cursor = new URL(route.request().url()).searchParams.get("cursor");
      cursors.push(cursor);
      return route.fulfill(
        json(
          cursor
            ? { notifications: Array.from({ length: 5 }, (_, i) => note(20 + i)), next_cursor: null, unread_count: 25 }
            : { notifications: Array.from({ length: 20 }, (_, i) => note(i)), next_cursor: "page-2", unread_count: 25 },
        ),
      );
    });
    await page.goto("/me/settings");
    await page.getByTestId("member-top-bar").getByRole("button", { name: "25 unread notifications" }).click();

    // Inside the drawer: Settings' «Delete notifications» card lists them too (ADR-460).
    const drawer = page.getByRole("dialog", { name: "Notifications" });
    await drawer.getByTestId("notifications-retry").click();
    await expect(drawer.getByText("Your password was reset")).toHaveCount(20);
    await drawer.getByRole("button", { name: "Load older notifications" }).click();
    await expect(drawer.getByText("Your password was reset")).toHaveCount(25);
    expect(cursors).toEqual([null, "page-2"]);
  });
  // ADR-460 (option B): trash and closed eye on hover or focus of a card
  // (fine pointer), behind the card and revealed by a swipe to the left
  // (touch); a delete offers «Undo» and the server restores it.
  test("a notification is deleted from the bell and brought back with Undo", async ({ page, isMobile }) => {
    const calls: string[] = [];
    await stub(page, {
      notifications: [
        {
          id: "n-1",
          user_id: user.id,
          organization_id: null,
          type: "password_reset_completed",
          payload: { url: "/me/settings#security" },
          read_at: null,
          inserted_at: new Date().toISOString(),
        },
      ],
    });
    await page.route("**/api/notifications/n-1", (route) => {
      calls.push(`${route.request().method()} n-1`);
      return route.fulfill(json({ deleted: true, restorable_for_seconds: 60 }));
    });
    await page.route("**/api/notifications/n-1/restore", (route) => {
      calls.push("restore n-1");
      return route.fulfill(json({ restored: true }));
    });
    await page.goto("/me/settings");
    await page.getByTestId("member-top-bar").getByRole("button", { name: "1 unread notification" }).click();

    const drawer = page.getByRole("dialog", { name: "Notifications" });
    const card = drawer.getByTestId("notification-card");
    if (isMobile) {
      // A real touch swipe to the left: the buttons sit behind the card until then.
      await swipeLeft(page, card.locator("article"));
      await expect(card).toHaveAttribute("data-revealed", "true");
      // Then the uncovered trash is pressed. (A synthetic CDP tap right after
      // the synthetic swipe is sometimes not turned into a click by Chromium.)
      await card.getByRole("button", { name: "Delete this notification" }).click();
      await expect(drawer.getByTestId("notification-undo-toast")).toContainText("Notification deleted");
    } else {
      await card.hover();
      await card.getByRole("button", { name: "Delete this notification" }).click();
      await expect(drawer.getByTestId("notification-undo-toast")).toContainText("Notification deleted");
    }
    await drawer.getByRole("button", { name: "Undo" }).click();
    await expect.poll(() => calls).toEqual(["DELETE n-1", "restore n-1"]);
  });

  test("Settings deletes every notification a filter matches, after a confirm", async ({ page }) => {
    const notes = Array.from({ length: 3 }, (_, i) => ({
      id: `n-${i}`,
      user_id: user.id,
      organization_id: null,
      type: "password_reset_completed",
      payload: {},
      read_at: new Date().toISOString(),
      inserted_at: new Date(Date.now() - i * 60_000).toISOString(),
    }));
    await stub(page);
    await page.route("**/api/notifications?**", (route) =>
      route.fulfill(json({ notifications: notes, next_cursor: null, unread_count: 0, matching_count: 3 })),
    );
    const bodies: unknown[] = [];
    await page.route("**/api/notifications/delete", (route) => {
      bodies.push(route.request().postDataJSON());
      return route.fulfill(json({ deleted_count: 3 }));
    });
    await page.goto("/me/settings#notifications");

    const card = page.getByTestId("notification-cleanup");
    await card.getByRole("radio", { name: "Read" }).click();
    await card.getByLabel("Select all (3)").check();
    await card.getByRole("button", { name: "Delete 3 notifications" }).click();
    await page.getByRole("dialog").getByTestId("notification-cleanup-confirm").click();
    await expect(card.getByText("3 notifications deleted.")).toBeVisible();
    expect(bodies).toEqual([{ filter: { state: "read" } }]);
  });
});
