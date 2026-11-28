import { expect, test, type Page, type Route } from "./support/test";

// ADR-760: the box's «Activity log». Staff (1A, 2A, 10A): a timeline grouped by
// the box's day, a row opens its details, «Only Maria K.» filters to her, «More»
// pages on with the cursor and the CSV export carries the same filters. The member
// (5A): Box › Subscription lists only what staff shared, by «The box». The API is
// stubbed; every route not listed answers an empty object.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

function tokenFor(sub: string, role: string) {
  const payload = Buffer.from(
    JSON.stringify({ sub, role, memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const ORGANIZATION = { id: "org-1", slug: "box1", name: "Box One", provider_kind: "gym", activation: "active", timezone: "UTC" };
const SETTINGS = { brand_name: "Box One", brand_logo_url: null, brand_primary_color: null };

function user(id: string, nickname: string, role: string) {
  return {
    id,
    nickname,
    role: "member",
    email: `${id}@example.com`,
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role, settings: {} }],
  };
}

const now = Date.now();
const iso = (minutesAgo: number) => new Date(now - minutesAgo * 60_000).toISOString();

function row(id: string, overrides: Record<string, unknown> = {}) {
  return {
    id,
    occurred_at: iso(10),
    action: "package.freeze",
    area: "packages",
    actor: { id: "staff-1", name: "Eleni S.", roles: ["front_desk"] },
    person: { id: "p1", name: "Maria K." },
    subject: {},
    subject_label: "Unlimited",
    details: { starts_on: "2026-12-01", ends_on: "2026-12-14" },
    reason: "Knee injury",
    reason_shared: true,
    sensitive: false,
    source: "request",
    redacted: false,
    ...overrides,
  };
}

async function signIn(page: Page, who: ReturnType<typeof user>, membership: Record<string, unknown>, extra: (route: Route, path: string, url: URL) => Promise<void> | undefined) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.addInitScript((view) => {
    window.localStorage.setItem("palee:selected-organization-slug", "box1");
    window.localStorage.setItem("palee.view", view);
  }, membership.role === "member" ? "member" : "staff");
  await page.route("**/api/**", async (route) => {
    const url = new URL(route.request().url());
    const path = tenantless(url.pathname);
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(who.id, "member"), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, who);
    if (path === "/api/memberships") return json(route, [membership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    const handled = extra(route, path, url);
    if (handled) return handled;
    return json(route, {});
  });
}

/** A button that is on screen and not under anything (a sticky bar, a sheet) before it is tapped. */
async function tap(page: Page, button: ReturnType<Page["getByRole"]>) {
  await expect(button).toBeVisible();
  await button.scrollIntoViewIfNeeded();
  await expect
    .poll(() =>
      button.evaluate((element) => {
        const box = element.getBoundingClientRect();
        const top = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2);
        return top !== null && (top === element || element.contains(top));
      }),
    )
    .toBe(true);
  await button.click();
}

test("staff: the timeline, a row's details, «Only Maria K.», «More» and the CSV with the same filters", async ({ page }) => {
  const reads: URL[] = [];
  const exports: URL[] = [];
  await signIn(
    page,
    user("owner-1", "Apostolos", "owner"),
    {
      id: "m-owner",
      role: "owner",
      roles: ["owner"],
      capabilities: { view_activity_members: "all", view_activity_packages: "all" },
      organization: ORGANIZATION,
      settings: SETTINGS,
    },
    (route, path, url) => {
      if (path === "/api/admin/activity-log/export") {
        exports.push(url);
        return route.fulfill({ status: 200, contentType: "text/csv", body: "when,who\n" });
      }
      if (path === "/api/admin/activity-log") {
        reads.push(url);
        if (url.searchParams.get("cursor") === "c2") {
          return json(route, {
            entries: [row("e3", { occurred_at: iso(60 * 24 * 3), action: "member.remove", area: "members", person: null, reason: null, redacted: true, reason_shared: false, subject_label: null, details: {} })],
            next_cursor: null,
            can_export: true,
            areas: ["members", "packages"],
          });
        }
        return json(route, {
          entries: [row("e1"), row("e2", { occurred_at: iso(30), action: "package.freeze_cancel", reason: null, reason_shared: false })],
          next_cursor: "c2",
          can_export: true,
          areas: ["members", "packages"],
        });
      }
      if (path === "/api/staff/members") return json(route, { staff: [{ user_id: "staff-1", nickname: "Eleni S." }] });
      return undefined;
    },
  );

  await page.goto("/admin/activity-log");
  const log = page.getByTestId("activity-log");
  await expect(log.getByTestId("activity-log-entry")).toHaveCount(2);
  await expect(log.getByText("Today", { exact: true })).toBeVisible();

  await tap(page, log.getByRole("button", { name: /Froze the subscription/ }));
  const detail = log.getByTestId("activity-log-detail");
  await expect(detail).toContainText("Knee injury");
  await expect(detail).toContainText("The member saw it too");
  await expect(detail).toContainText("Yes");

  await tap(page, detail.getByRole("button", { name: "Only Maria K." }));
  await expect.poll(() => reads.some((url) => url.searchParams.get("person_id") === "p1")).toBe(true);
  await expect(page.getByTestId("activity-log-person-chip")).toContainText("Maria K.");

  await tap(page, page.getByRole("button", { name: "More" }));
  await expect.poll(() => reads.some((url) => url.searchParams.get("cursor") === "c2" && url.searchParams.get("person_id") === "p1")).toBe(true);
  await expect(log.getByTestId("activity-log-entry")).toHaveCount(3);
  await expect(log.getByTestId("activity-log-entry").last()).toContainText("Deleted member");

  await tap(page, page.getByRole("button", { name: "Export CSV" }));
  await expect.poll(() => exports.map((url) => url.searchParams.get("person_id"))).toEqual(["p1"]);
  expect(exports[0].searchParams.get("cursor")).toBeNull();
});

test("staff: no export button when the page says can_export is false", async ({ page }) => {
  await signIn(
    page,
    user("coach-1", "Nikos", "coach"),
    { id: "m-coach", role: "coach", roles: ["coach"], capabilities: { view_activity_classes: "own" }, organization: ORGANIZATION, settings: SETTINGS },
    (route, path) => {
      if (path === "/api/admin/activity-log") {
        return json(route, { entries: [row("e1", { area: "classes", action: "class.update", person: null })], next_cursor: null, can_export: false, areas: ["classes"] });
      }
      if (path === "/api/staff/members") return json(route, { staff: [] });
      return undefined;
    },
  );

  await page.goto("/admin/activity-log");
  await expect(page.getByTestId("activity-log-entry")).toHaveCount(1);
  await expect(page.getByTestId("activity-log-export")).toHaveCount(0);
  await expect(page.getByRole("button", { name: "More" })).toHaveCount(0);
});

test("member: Box › Subscription lists what the box shared, by «The box»", async ({ page }) => {
  const reads: URL[] = [];
  await signIn(
    page,
    user("maria", "Maria", "member"),
    { id: "m-1", role: "member", roles: ["member"], capabilities: {}, home_location_id: "loc-1", organization: ORGANIZATION, settings: SETTINGS },
    (route, path, url) => {
      if (path === "/api/me/membership/activity") {
        reads.push(url);
        return json(route, {
          entries: [1, 2, 3, 4].map((n) => ({
            id: `a${n}`,
            occurred_at: iso(60 * 24 * n),
            action: "package.freeze",
            area: "packages",
            person: { id: "maria", name: "Maria" },
            subject: {},
            subject_label: "Unlimited",
            details: {},
            reason: n === 1 ? "Knee injury" : null,
            redacted: false,
          })),
          next_cursor: null,
        });
      }
      return undefined;
    },
  );

  await page.goto("/box");
  const history = page.getByTestId("member-activity");
  await expect(history.getByTestId("member-activity-entry")).toHaveCount(3);
  await expect(history.getByTestId("member-activity-entry").first()).toContainText("The box");
  await expect(history.getByTestId("member-activity-entry").first()).toContainText("Reason: Knee injury");
  await expect(history).not.toContainText("Eleni");
  expect(reads[0].pathname).toBe("/api/org/box1/me/membership/activity");

  await tap(page, history.getByRole("button", { name: "More" }));
  await expect(history.getByTestId("member-activity-entry")).toHaveCount(4);
});
