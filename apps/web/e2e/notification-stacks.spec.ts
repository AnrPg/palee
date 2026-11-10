import { expect, test, type Page } from "./support/test";

// ADR-600: similar notifications stack in the bell. The server answers one
// row per stack (`stacks=true`), the deck shows «+N more similar», a tap opens
// it in place (by `group_key`), and the stack's trash deletes all of it with
// «Undo» restoring all of it. The tabs filter on the server (`types`). The API
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

async function stubBase(page: Page, { staff = false, notifications = [] as unknown[] } = {}) {
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


const key = "class_workout_missing:o:org-1:d:2026-11-10";

const wod = (index: number, extra: Record<string, unknown> = {}) => ({
  id: `w-${index}`,
  user_id: user.id,
  organization_id: "org-1",
  type: "class_workout_missing",
  group_key: key,
  payload: { class_name: `CrossFit ${7 + index}:00`, class_when: "Tue 10 Nov", url: "/admin/schedule" },
  read_at: null,
  inserted_at: new Date(Date.now() - index * 60_000).toISOString(),
  ...extra,
});

const members = [0, 1, 2, 3].map((index) => wod(index));
const stackRow = wod(0, { stack: { key, count: 4, unread_count: 4 } });

async function stub(page: Page) {
  await stubBase(page);
  const requests: URLSearchParams[] = [];
  const bodies: { path: string; body: unknown }[] = [];
  await page.route("**/api/notifications/unread-count", (route) => route.fulfill(json({ unread_count: 4 })));
  await page.route("**/api/notifications?**", (route) => {
    const params = new URL(route.request().url()).searchParams;
    requests.push(params);
    const rows = params.get("group_key") ? members : [stackRow];
    return route.fulfill(json({ notifications: rows, next_cursor: null, unread_count: 4 }));
  });
  for (const path of ["delete", "restore", "read"]) {
    await page.route(`**/api/notifications/${path}`, (route) => {
      bodies.push({ path, body: route.request().postDataJSON() });
      return route.fulfill(
        json(
          path === "delete"
            ? { deleted_count: 4, restorable_for_seconds: 60 }
            : path === "restore"
              ? { restored_count: 4 }
              : { marked_count: 4 },
        ),
      );
    });
  }
  return { requests, bodies };
}

async function openBell(page: Page) {
  await page.goto("/me/settings");
  await page.getByTestId("member-top-bar").getByRole("button", { name: "4 unread notifications" }).click();
  return page.getByRole("dialog", { name: "Notifications" });
}

test.describe("notification stacks (ADR-600)", () => {
  test("similar notifications show as one deck that opens in place", async ({ page }) => {
    const { requests } = await stub(page);
    const drawer = await openBell(page);

    const stack = drawer.getByTestId("notification-stack");
    await expect(stack).toHaveCount(1);
    await expect(stack.getByTestId("notification-stack-more")).toHaveText("+3 more similar");
    await expect(stack.getByTestId("notification-new-badge")).toHaveText("4 new");
    expect(requests[0].get("stacks")).toBe("true");

    await stack.locator("article").click();
    const opened = drawer.getByTestId("notification-stack-open");
    await expect(opened).toContainText("4 similar notifications");
    await expect(opened.getByTestId("notification-card")).toHaveCount(4);
    expect(requests.some((params) => params.get("group_key") === key)).toBe(true);

    await opened.getByTestId("notification-stack-collapse").click();
    await expect(drawer.getByTestId("notification-stack")).toHaveCount(1);
  });

  test("the trash of a stack deletes all of it and Undo brings all of it back", async ({ page, isMobile }) => {
    test.skip(isMobile, "the touch swipe is covered by notification-settings.spec.ts");
    const { bodies } = await stub(page);
    const drawer = await openBell(page);

    const card = drawer.getByTestId("notification-stack").getByTestId("notification-card");
    await card.hover();
    await card.getByRole("button", { name: "Delete all of these similar notifications" }).click();
    await expect(drawer.getByTestId("notification-undo-toast")).toContainText("4 notifications deleted.");
    await drawer.getByRole("button", { name: "Undo" }).click();

    await expect
      .poll(() => bodies)
      .toEqual([
        { path: "delete", body: { filter: { group_key: key } } },
        { path: "restore", body: { filter: { group_key: key } } },
      ]);
  });

  test("the closed eye of a stack marks all of it read", async ({ page, isMobile }) => {
    test.skip(isMobile, "the touch swipe is covered by notification-settings.spec.ts");
    const { bodies } = await stub(page);
    const drawer = await openBell(page);

    const card = drawer.getByTestId("notification-stack").getByTestId("notification-card");
    await card.hover();
    await card.getByRole("button", { name: "Mark all of these as read" }).click();
    await expect.poll(() => bodies).toEqual([{ path: "read", body: { filter: { group_key: key } } }]);
  });

  test("a tab asks the server for its types", async ({ page }) => {
    const { requests } = await stub(page);
    const drawer = await openBell(page);

    await drawer.getByRole("radio", { name: "Bookings" }).click();
    await expect.poll(() => requests.some((params) => params.get("types")?.includes("booking_approved"))).toBe(true);
  });
});
