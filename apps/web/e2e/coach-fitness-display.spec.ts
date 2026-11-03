import { expect, test, type Page, type Request } from "./support/test";

// ADR-395: on a client's profile (Training tab) the client's coach reads their
// body weight and birth year and picks what the client's «Fitness level» card
// shows: their own choice, «Progress only» or «Nothing», saved with the
// profile's save bar. Staff who do not coach the client (403 not_your_client)
// see no panel and none of the personal values. The API is stubbed; every
// route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

async function asCoach(page: Page) {
  const user = {
    id: "coach-1",
    nickname: "Kostas",
    role: "member",
    email: "coach@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "kypseli", role: "coach", settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const token = `stub.${payload}.signature`;

  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(
      json([
        {
          role: "coach",
          roles: ["coach"],
          capabilities: { view_client_training: true, manage_coaching: true },
          organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" },
          settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
        },
      ]),
    ),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/org/*/admin/users/u-1", (route) =>
    route.fulfill(
      json({
        user: {
          identity: { id: "u-1", nickname: "Eleni", avatar_url: null, role: "member", joined_at: "2026-01-10T10:00:00Z" },
          account_status: "active",
          membership: { roles: ["member"], coach_scope: "assigned" },
          available_sections: [],
          attention: [],
          operational_links: {},
        },
      }),
    ),
  );
  await page.route("**/api/org/*/admin/users/u-1/prs", (route) => route.fulfill(json({ user_id: "u-1", visibility: "coach", member: null, prs: [] })));
}

test.describe("coach and a client's fitness card (ADR-395)", () => {
  test("the coach reads weight and birth year and sets «Nothing», then gives the choice back", async ({ page }) => {
    // Desktop layout: on a phone this picker is a combobox (SegmentPicker collapses).
    await page.setViewportSize({ width: 1280, height: 800 });
    const server = { settings: { body_weight_kg: 64, birth_year: 1991, display: "progress_only" }, override: null as string | null };
    const puts: Array<Record<string, unknown>> = [];
    await asCoach(page);
    await page.route("**/api/org/*/staff/clients/u-1/fitness-display", (route) => {
      if (route.request().method() === "PUT") {
        const body = bodyOf(route.request());
        puts.push(body);
        server.override = body.display;
      }
      return route.fulfill(json(server));
    });

    await page.goto("/admin/users/u-1?tab=training");
    const panel = page.getByTestId("client-fitness-display");
    await expect(panel.getByTestId("client-fitness-facts")).toContainText("64 kg", { timeout: 60_000 });
    await expect(panel.getByTestId("client-fitness-facts")).toContainText("1991");
    await expect(panel.getByRole("radio", { name: "Their choice (Progress only)" })).toHaveAttribute("aria-checked", "true");
    await expect(panel).toContainText("their card says “Set by your coach”");

    await panel.getByRole("radio", { name: "Nothing" }).click();
    await expect(page.getByTestId("profile-save-bar-count")).toHaveText("1 unsaved change");
    await page.getByTestId("profile-save-bar-save").click();
    await expect(page.getByTestId("profile-save-bar")).toContainText("Changes saved.");
    expect(puts).toEqual([{ display: "none" }]);

    await panel.getByRole("radio", { name: "Their choice (Progress only)" }).click();
    await page.getByTestId("profile-save-bar-save").click();
    await expect.poll(() => puts).toEqual([{ display: "none" }, { display: null }]);
  });

  test("staff who do not coach the client see no panel and no personal values", async ({ page }) => {
    await asCoach(page);
    await page.route("**/api/org/*/staff/clients/u-1/fitness-display", (route) =>
      route.fulfill(json({ error: { code: "not_your_client", message: "Not one of your clients" } }, 403)),
    );

    await page.goto("/admin/users/u-1?tab=training");
    await expect(page.getByRole("tab", { name: "Training" })).toHaveAttribute("aria-selected", "true", { timeout: 60_000 });
    await expect(page.getByTestId("client-fitness-display")).toHaveCount(0);
    await expect(page.locator("#fitness_display")).toHaveCount(0);
  });
});
