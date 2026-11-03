import { expect, test, type Page } from "./support/test";

// Staff home, layout B (ANR picked it 2026-11-03 from three mockups): the
// cards "looked randomly thrown". Now: «Σήμερα» (today's classes and the
// coach's own appointments, by time) beside «Θέλει προσοχή» (which also counts
// the coach's unanswered messages, technique videos and scaling suggestions,
// each opening its tab), then «Οι άνθρωποί σου». The API is stubbed.

const user = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner-1@example.com",
  email_verified: true,
  completed_tours: ["admin-dashboard", "admin", "first_run"],
  preferred_locale: "el",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

function tokenFor() {
  const payload = Buffer.from(JSON.stringify({ sub: user.id, role: user.role, exp: Math.floor(Date.now() / 1000) + 3600 })).toString("base64url");
  return `stub.${payload}.signature`;
}

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

/** Today at the given local hour, so the slots always fall on "today". */
function todayAt(hour: number) {
  const date = new Date();
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

async function stubApi(page: Page, extraCapabilities: Record<string, boolean> = {}) {
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: tokenFor(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "owner",
          roles: ["owner", "coach"],
          capabilities: {
            grant_staff_roles: true,
            manage_coaching: true,
            manage_appointments: true,
            run_classes: true,
            manage_schedule: true,
            check_in: true,
            view_spaces: true,
            manage_shop: true,
            take_payments: true,
            ...extraCapabilities,
          },
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/org/*/admin/onboarding", (route) =>
    route.fulfill(json({ audience: "gym", steps: [], completed_count: 0, total: 0, finished: true, dismissed: true, tour_completed: true })),
  );
  await page.route("**/schedule?**", (route) =>
    route.fulfill(
      json({
        slots: [{ id: "slot-1", name: "CrossFit", scheduled_at: todayAt(12), capacity: 14, approved_booking_count: 9, bookings: [] }],
      }),
    ),
  );
  await page.route("**/staff/appointment-slots**", (route) =>
    route.fulfill(
      json({
        slots: [
          {
            id: "appt-1",
            kind: "pt_session",
            starts_at: todayAt(13),
            ends_at: todayAt(14),
            capacity: 1,
            cancelled_at: null,
            bookings: [{ id: "b-1", status: "booked", nickname: "Maria K" }],
          },
        ],
      }),
    ),
  );
  await page.route("**/staff/reply-queue", (route) =>
    route.fulfill(
      json({
        replies: [
          { id: "r-1", client_nickname: "Maria K", sent_at: todayAt(8), due_at: todayAt(9), overdue: true },
          { id: "r-2", client_nickname: "Nikos B", sent_at: todayAt(10), due_at: null, overdue: false },
        ],
      }),
    ),
  );
  await page.route("**/staff/coaching-relationships**", (route) => route.fulfill(json({ relationships: [] })));
  await page.route("**/api/org/kypseli/community/squads", (route) =>
    route.fulfill(
      json({
        organization_id: "org-1",
        can_create: true,
        limits: { max_members: 30, max_live_squads: 20 },
        coached: [],
        archived: [],
        joined: [],
        invites: [],
        clients: [],
      }),
    ),
  );
  await page.route("**/staff/form-reviews**", (route) => route.fulfill(json({ form_reviews: [{ id: "fr-1" }] })));
  await page.route("**/staff/scaling-suggestions", (route) => route.fulfill(json({ suggestions: [{ id: "s-1" }, { id: "s-2" }, { id: "s-3" }] })));
}

test.describe("staff home layout", () => {
  test.beforeEach(async ({ page, context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "el", url: baseURL! }]);
    await stubApi(page);
    await page.goto("/org/kypseli/admin");
  });

  test("«Σήμερα» lists classes and appointments together by time", async ({ page }) => {
    const today = page.locator("#home-today");
    await expect(today).toContainText("Σήμερα");
    const rows = today.getByRole("listitem");
    await expect(rows).toHaveCount(2);
    await expect(rows.nth(0)).toContainText("CrossFit");
    await expect(rows.nth(0).getByTestId("timeline-kind")).toHaveText("Τμήμα");
    await expect(rows.nth(1)).toContainText("Προσωπική προπόνηση · Maria K");
    await expect(rows.nth(1).getByTestId("timeline-kind")).toHaveText("Ραντεβού");
    await expect(today.getByTestId("home-week-appointments")).toHaveAttribute("href", "/org/kypseli/admin/appointments");
  });

  test("the coach's queues are rows in «Θέλει προσοχή», not cards", async ({ page }) => {
    const attention = page.locator("#home-attention");
    const replies = attention.getByRole("link", { name: /2 μηνύματα περιμένουν απάντηση/ });
    await expect(replies).toContainText("1 εκπρόθεσμο");
    await expect(replies).toHaveAttribute("href", "/org/kypseli/admin/coaching?tab=replies");
    await expect(attention.getByRole("link", { name: "1 βίντεο τεχνικής περιμένει έλεγχο" })).toHaveAttribute(
      "href",
      "/org/kypseli/admin/coaching?tab=form-reviews",
    );
    await expect(attention.getByRole("link", { name: "3 προτάσεις κλιμάκωσης" })).toHaveAttribute(
      "href",
      "/org/kypseli/admin/coaching?tab=scaling",
    );

    // The old separate cards are gone.
    await expect(page.getByText("Ουρά ελέγχων τεχνικής")).toHaveCount(0);
    await expect(page.getByText("Αναμένουν απάντηση")).toHaveCount(0);
    await expect(page.getByText("Τα ραντεβού μου")).toHaveCount(0);
    await expect(page.getByText("PR μελών box")).toHaveCount(0);
  });

  test("«Οι άνθρωποί σου» comes after today and attention, with one member search", async ({ page }) => {
    const people = page.locator("#home-people");
    await expect(people.getByRole("heading", { name: "Οι άνθρωποί σου" })).toBeVisible();
    await expect(people.getByRole("textbox", { name: "Βρες μέλος του box: προφίλ και PR" })).toBeVisible();
    await expect(people.locator("#home-my-clients")).toBeVisible();

    // Clients and coach groups share one row, at the same height (desktop).
    const squads = people.locator("#home-my-squads");
    await expect(squads).toBeVisible();
    const clientsBox = await people.locator("#home-my-clients").boundingBox();
    const squadsBox = await squads.boundingBox();
    if ((page.viewportSize()?.width ?? 0) >= 768) {
      expect(Math.abs(clientsBox!.y - squadsBox!.y)).toBeLessThan(1);
      expect(Math.abs(clientsBox!.height - squadsBox!.height)).toBeLessThan(1);
    }

    const attentionBox = await page.locator("#home-attention").boundingBox();
    const peopleBox = await people.boundingBox();
    expect(attentionBox && peopleBox && peopleBox.y > attentionBox.y + attentionBox.height - 1).toBe(true);
  });

  test("header shortcuts skip pages the top bar already links to", async ({ page }) => {
    const shortcuts = page.getByTestId("home-header-shortcut");
    // Οικονομικά and Κατάστημα are in the top bar, so the header offers check-in and spaces.
    await expect(shortcuts).toHaveText(["Check-in", "Χώροι"]);
    await expect(shortcuts.first()).toHaveAttribute("href", "/org/kypseli/admin/check-in");
  });

  test("every tool shows its label first and a coloured line icon on the right", async ({ page }) => {
    const tile = page.getByRole("link", { name: "Χώροι" }).last();
    const label = await tile.getByText("Χώροι").boundingBox();
    const icon = await tile.getByTestId("hub-tile-icon").boundingBox();
    expect(icon!.x).toBeGreaterThan(label!.x + label!.width - 1);
    expect(Math.abs(icon!.y + icon!.height / 2 - (label!.y + label!.height / 2))).toBeLessThan(4);
  });

  test("the page never scrolls sideways", async ({ page }) => {
    await expect(page.locator("#home-people")).toBeVisible();
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow).toBeLessThanOrEqual(0);
  });
});

// «Περιεχόμενο» (ANR, 2026-11-03): what the box writes and publishes, and a
// tool group that would hold a single tile is folded into «Διαχείριση».
test.describe("staff home tools", () => {
  test.beforeEach(async ({ context, baseURL }) => {
    await context.addCookies([{ name: "palee_locale", value: "el", url: baseURL! }]);
  });

  test("a lone content tile joins «Διαχείριση» and its group is hidden", async ({ page }) => {
    await stubApi(page);
    await page.goto("/org/kypseli/admin");
    await expect(page.getByRole("link", { name: "Διατροφικά πλάνα" })).toBeVisible();
    await expect(page.getByText("Περιεχόμενο", { exact: true })).toHaveCount(0);
  });

  test("an owner's content group holds the vault, plans, public page and documents", async ({ page }) => {
    await stubApi(page, { manage_workouts: true, manage_settings: true, view_business_analytics: true });
    await page.goto("/org/kypseli/admin");
    // An owner's header: check-in, analytics, then spaces (the shop is in the top bar; ANR kept it there only).
    await expect(page.getByTestId("home-header-shortcut")).toHaveText(["Check-in", "Στατιστικά & Μάρκετινγκ", "Χώροι"]);
    const group = page.getByText("Περιεχόμενο", { exact: true }).locator("..");
    await expect(group.getByRole("link")).toHaveText(["Αρχείο WOD", "Διατροφικά πλάνα", "Δημόσια σελίδα", "Έγγραφα"]);
    await expect(group.getByRole("link", { name: "Έγγραφα" })).toHaveAttribute("href", "/org/kypseli/admin/documents");
  });
});
