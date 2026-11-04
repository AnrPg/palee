import { expect, test, type Page, type Route } from "./support/test";

// ADR-397: reports on box reviews. A member reports another member's review
// from its ⋯ in Box › «Reviews» (the review stays up, marked «You reported
// it»); the Palee team decides in Platform console › «Review reports» (keep
// in one tap; hide and remove need a ground and the text the author reads),
// and restores a hidden review from «Decided». The API is stubbed.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

type Write = { path: string; method: string; body: unknown };

function tokenFor(user: { id: string; role: string }) {
  const payload = Buffer.from(JSON.stringify({ sub: user.id, role: user.role, memberships: [], exp: Math.floor(Date.now() / 1000) + 3600 })).toString("base64url");
  return `stub.${payload}.signature`;
}

async function signedIn(page: Page, user: { id: string; role: string } & Record<string, unknown>, writes: Write[], extra: (path: string, method: string, route: Route) => Promise<void> | null, memberships: unknown[] = []) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const url = new URL(route.request().url());
    const path = tenantless(url.pathname);
    const method = route.request().method();
    if (method !== "GET") writes.push({ path, method, body: route.request().postDataJSON() });
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(user), refresh_token: "refresh", user });
    if (path === "/api/auth/me") return json(route, user);
    if (path === "/api/memberships") return json(route, memberships);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    const handled = extra(path + url.search, method, route);
    if (handled) return handled;
    return json(route, {});
  });
}

const reviews = [
  { id: "review-1", author_name: "Nikos", body: "The coach is useless. Don't go.", rating: 1, created_at: "2026-11-02T10:00:00Z", edited_at: null, reply: null },
  { id: "review-2", author_name: "Eleni", body: "Good coaches.", rating: 4, created_at: "2026-10-28T10:00:00Z", edited_at: null, reply: null },
];

test.describe("a member reports a review", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("from its ⋯ in Box: a reason, a note when needed, then «You reported it»", async ({ page }) => {
    const writes: Write[] = [];
    let reported: string[] = [];
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
    const membership = {
      role: "member",
      roles: ["member"],
      capabilities: {},
      organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", activation: "active", timezone: "Europe/Athens", timezone_confirmed: true },
      settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
    };
    await signedIn(
      page,
      member,
      writes,
      (path, method, route) => {
        if (path === "/api/me/box-reviews") {
          return json(route, { average: 2.5, count: 2, can_review: true, has_more: false, google: null, mine: null, reported_ids: reported, reviews });
        }
        if (path === "/api/me/box-reviews/review-1/report" && method === "POST") {
          reported = ["review-1"];
          return json(route, { review_id: "review-1", status: "open" });
        }
        return null;
      },
      [membership],
    );
    await page.goto("/box");

    const section = page.getByTestId("box-reviews");
    await section.getByRole("button", { name: "More about this review" }).first().click();
    await page.getByRole("menuitem", { name: "Report" }).click();
    const sheet = page.getByRole("dialog", { name: "Report review" });
    await expect(sheet).toContainText("Only the Palee team sees it.");
    await sheet.getByRole("button", { name: "Send report" }).click();
    await expect(sheet.getByText("Choose a reason.")).toBeVisible();
    await sheet.getByRole("radio", { name: /Something else/ }).click();
    await sheet.getByRole("button", { name: "Send report" }).click();
    await expect(sheet.getByText("Write a few words so we understand what's wrong.")).toBeVisible();
    await sheet.getByLabel("What's wrong?").fill("Fake account");
    await sheet.getByRole("button", { name: "Send report" }).click();
    await expect(page.getByRole("dialog", { name: "Thank you" })).toBeVisible();
    expect(writes.find((write) => write.path === "/api/me/box-reviews/review-1/report")?.body).toEqual({ reason: "other", note: "Fake account" });
    await page.getByRole("button", { name: "OK" }).click();
    await expect(section.getByTestId("box-review-reported")).toHaveText("You reported it · waiting for the Palee team");
  });
});

test.describe("Platform console › Review reports", () => {
  const vendor = {
    id: "vendor-1",
    nickname: "Palee",
    role: "admin",
    email: "vendor-1@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: true,
    memberships: [],
  };
  const item = {
    review_id: "review-1",
    organization: { id: "org-1", name: "Box Kypseli" },
    author_name: "Nikos",
    box_reported: false,
    reports_count: 1,
    first_reported_at: "2026-11-03T08:00:00Z",
    reasons: [{ reason: "offensive", count: 1 }],
    notes: [],
    reported: { rating: 1, body: "The coach is useless. Don't go." },
    current: { rating: 1, body: "The coach is useless. Don't go.", edited_at: null },
  };
  const hidden = {
    id: "decision-1",
    review_id: "review-1",
    organization: item.organization,
    outcome: "hide",
    ground: "offensive",
    statement: "It insults a coach by name.",
    reports_count: 1,
    decided_by: "Palee",
    decided_at: "2026-11-03T10:00:00Z",
    review_status: "hidden",
  };

  test("hiding needs the author's text; then the review can be restored from «Decided»", async ({ page }) => {
    const writes: Write[] = [];
    let items = [item];
    let decisions: (typeof hidden)[] = [];
    await signedIn(page, vendor, writes, (path, method, route) => {
      if (path === "/api/platform/review-reports?status=open") return json(route, { items, decisions: [] });
      if (path === "/api/platform/review-reports?status=decided") return json(route, { items: [], decisions });
      if (path === "/api/platform/review-reports/review-1/decision" && method === "POST") {
        items = [];
        decisions = [hidden];
        return json(route, { review_id: "review-1", outcome: "hide", ground: "offensive", resolved: 1 });
      }
      if (path === "/api/platform/review-reports/review-1/restore" && method === "POST") {
        decisions = [{ ...hidden, id: "decision-2", outcome: "restore", ground: "no_violation", review_status: "visible" }, { ...hidden, review_status: "visible" }];
        return json(route, { review_id: "review-1", outcome: "restore", ground: "no_violation", resolved: 0 });
      }
      return null;
    });
    await page.goto("/platform/review-reports");

    await expect(page.getByRole("heading", { name: "Review reports" })).toBeVisible();
    const card = page.getByTestId("review-report-review-1");
    await expect(card).toContainText("Box Kypseli · Nikos");
    await card.getByRole("button", { name: "Hide" }).click();
    await card.getByRole("button", { name: "Hide review" }).click();
    await expect(card.getByText("Write what the author will read.")).toBeVisible();
    await card.getByLabel("What we tell the author").fill("It insults a coach by name.");
    await card.getByRole("button", { name: "Hide review" }).click();
    await expect(page.getByText("Decided. 1 report closed.")).toBeVisible();
    expect(writes.find((write) => write.path === "/api/platform/review-reports/review-1/decision")?.body).toEqual({
      outcome: "hide",
      ground: "offensive",
      statement: "It insults a coach by name.",
    });

    await page.getByRole("tab", { name: "Decided" }).click();
    await page.getByTestId("review-restore").click();
    const dialog = page.getByRole("dialog", { name: "Restore review" });
    await dialog.getByLabel("What we tell the author").fill("On a second look it does not break the terms.");
    await dialog.getByRole("button", { name: "Restore review" }).click();
    await expect(page.getByText("The review shows again. The author was notified.")).toBeVisible();
    expect(writes.find((write) => write.path === "/api/platform/review-reports/review-1/restore")?.body).toEqual({
      statement: "On a second look it does not break the terms.",
    });
    await expect(page.getByTestId("review-restore")).toHaveCount(0);
  });
});
