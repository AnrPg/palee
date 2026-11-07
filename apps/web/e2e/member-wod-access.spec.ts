import { expect, test, type Page, type Route } from "./support/test";

// ADR-551 (ANR's picks 1A, 2A, 3B, 2026-11-07): with the member's access
// closed the server sends no WOD, and Box shows the WOD of the day, the
// «My workouts» tile and its tab greyed with a lock, not pressable. With
// access open the tile leads to the programme, and on a wide screen the Box
// tab strip sits under the logo. The API is stubbed; every other route
// answers an empty object.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

const member = {
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

function memberToken() {
  const payload = Buffer.from(
    JSON.stringify({ sub: member.id, role: member.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

function localToday() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}
function todayAt(hour: number) {
  const date = new Date();
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

const fran = { id: "wod-1", title: "Fran", type: "crossfit", authoring_mode: "free_text", free_text_body: "21-15-9\nThrusters 43/30 kg\nPull-ups", sections: [] };

function entitlement(open: boolean) {
  return {
    status: open ? "active" : "blocked",
    source: open ? "membership_package" : "overdue_invoice",
    grace_until: null,
    workouts_open: open,
    enforcement_mode: "enforce_all",
    plan: null,
    allowances: {},
    usage_entries: [],
  };
}

async function stubMember(page: Page, open: boolean) {
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    if (path === "/api/auth/refresh") return json(route, { access_token: memberToken(), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, member);
    if (path === "/api/memberships") {
      return json(route, [
        {
          role: "member",
          roles: ["member"],
          capabilities: {},
          organization: { id: "org-1", slug: "kypseli", name: "Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]);
    }
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [] });
    if (path === "/api/me/entitlement") return json(route, { entitlement: entitlement(open) });
    if (path === "/api/schedule") {
      return json(route, {
        start_date: localToday(),
        end_date: localToday(),
        days: 7,
        class_types: [],
        slots: [
          {
            id: "slot-1",
            master_workout_id: "wod-1",
            name: "CrossFit",
            duration_minutes: 60,
            scheduled_at: todayAt(23),
            class_type_id: "ct-1",
            class_type: { id: "ct-1", name: "CrossFit" },
            capacity: 12,
            auto_approve: true,
            booking_timeout_minutes: 30,
            approved_booking_count: 4,
            spots_remaining: 8,
            // The server drops the WOD while access is closed.
            workout: open ? fran : null,
            wod_locked: !open,
            current_user_booking: null,
            bookings: [],
          },
        ],
      });
    }
    if (path === "/api/my-workouts") {
      return open
        ? json(route, { start_date: localToday(), end_date: localToday(), assignments: [] })
        : json(route, { code: "finance_entitlement_blocked", error: "Finance entitlement blocked" }, 403);
    }
    if (path === "/api/executions") return json(route, { executions: [] });
    if (path === "/api/me/training-log/sources") return json(route, { available_sources: ["class", "freeform"], classes: [], assignments: [], library_workouts: [] });
    if (path === "/api/me/exercise-suggestions") return json(route, { groups: [] });
    if (/\/injury-warnings$/.test(path)) return json(route, { level: "none", warnings: [], warning_count: 0 });
    return json(route, {});
  });
}

test.describe("closed access (mockup 3 B)", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("shows the WOD of the day, the tile and the tab greyed with a lock, and the programme page refuses", async ({ page }) => {
    await stubMember(page, false);
    await page.goto("/box");

    const today = page.getByTestId("box-today-locked");
    await expect(today).toBeVisible();
    await expect(today).toContainText("Opens once your membership is active");
    await expect(page.getByRole("heading", { name: "Fran" })).toHaveCount(0);

    const tile = page.getByRole("link", { name: "My Workouts. Opens once your membership is active" });
    await expect(tile).toBeVisible();
    await expect(tile).toHaveAttribute("aria-disabled", "true");
    await expect(tile).not.toHaveAttribute("href", /.*/);

    await page.getByRole("link", { name: "Schedule" }).first().click();
    await expect(page).toHaveURL(/\/box\/schedule/);
    const tab = page.locator("nav[data-tabs]").getByRole("link", { name: "My Workouts. Opens once your membership is active" });
    await expect(tab).toHaveAttribute("aria-disabled", "true");

    await page.goto("/box/workouts");
    await expect(page.getByText("Your access is paused because a payment is overdue. Settle the balance to see your workouts again.")).toBeVisible();
  });
});

test.describe("open access", () => {
  test("the tile opens the programme; on a wide screen the tabs sit under the logo (mockups 1 A, 2 A)", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await stubMember(page, true);
    await page.goto("/box");

    const tile = page.getByRole("link", { name: "My Workouts", exact: true }).first();
    await expect(tile).toHaveAttribute("href", /\/box\/workouts$/);
    await tile.click();
    await expect(page).toHaveURL(/\/box\/workouts$/);

    const logo = await page.getByTestId("member-top-bar").getByRole("link", { name: "Palee" }).boundingBox();
    const firstTab = await page.locator("nav[data-tabs] a").first().boundingBox();
    expect(logo && firstTab).toBeTruthy();
    // Same column: the first tab starts within a few pixels of the logo.
    expect(Math.abs(firstTab!.x - logo!.x)).toBeLessThan(8);
  });
});
