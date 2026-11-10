import { expect, test, type Page, type Request } from "./support/test";

// ADR-612, staff side: «Gift or grace» on a box member's profile (Finance
// tab). Staff who take payments give a grace until a date; the history shows
// who gave it, when and why, and it can be revoked. The API is stubbed; every
// route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

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
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const token = `stub.${payload}.signature`;
  const membership = {
    role: "owner",
    roles: ["owner"],
    capabilities: { manage_billing: "all", take_payments: "all", manage_memberships: "all" },
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
}

test.describe("member benefits (staff)", () => {
  test("staff give a grace until a date and revoke it, with who and why kept", async ({ page }) => {
    const calls: Array<{ path: string; body: Record<string, unknown> }> = [];
    let benefits: Array<Record<string, unknown>> = [];
    await asOwner(page);
    await page.route("**/api/org/box1/admin/users/u-2", (route) =>
      route.fulfill(
        json({
          user: {
            identity: { id: "u-2", nickname: "Kostas", avatar_url: null, role: "member", joined_at: "2026-01-10T00:00:00Z" },
            account_status: "active",
            membership: { roles: ["member"], coach_scope: "own" },
            available_sections: ["overview", "finance"],
            attention: [],
            operational_links: {},
          },
        }),
      ),
    );
    await page.route("**/api/org/box1/admin/users/u-2/finance", (route) =>
      route.fulfill(
        json({
          user_id: "u-2",
          available: true,
          summary: { credit_balance: 0, current_status: { state: "overdue" }, package_relationship: {}, outstanding_items: [], effective_entitlement: null },
          details: {
            membership: { id: "m-2", status: "overdue", starts_on: "2026-01-10" },
            package_subscriptions: [],
            referral_claims: [],
            referred_members: [],
            referral_rewards: [],
          },
          drill_down: null,
          operational_links: {},
        }),
      ),
    );
    await page.route("**/api/org/box1/admin/finance/members/u-2/benefits**", (route) => {
      const request = route.request();
      const path = new URL(request.url()).pathname;
      if (request.method() === "GET") return route.fulfill(json({ benefits }));
      const body = bodyOf(request);
      calls.push({ path, body });
      const given = {
        id: "b-1",
        action: "grant",
        kind: "grace",
        state: path.endsWith("/revoke") ? "revoked" : "active",
        starts_on: "2026-11-10",
        ends_on: path.endsWith("/revoke") ? benefits[0]?.ends_on : body.ends_on,
        amount_cents: null,
        details: {},
        reason: path.endsWith("/revoke") ? benefits[0]?.reason : body.reason,
        given_by_id: "owner-1",
        given_by_name: "Olga",
        given_by_roles: ["owner"],
        given_at: "2026-11-10T10:00:00Z",
        request_id: "req-1",
        revocation: path.endsWith("/revoke")
          ? { reason: body.reason, by_id: "owner-1", by_name: "Olga", by_roles: ["owner"], at: "2026-11-10T11:00:00Z", request_id: "req-2" }
          : null,
      };
      benefits = [given];
      return route.fulfill(json({ benefit: given, replayed: false }, path.endsWith("/revoke") ? 200 : 201));
    });

    await page.goto("/admin/users/u-2?tab=finance");
    const card = page.getByTestId("member-benefits");
    await expect(card.getByText("Nothing has been given yet.")).toBeVisible();

    await card.getByTestId("member-benefit-open").click();
    const sheet = page.getByRole("dialog");
    await sheet.getByTestId("member-benefit-kind-grace").click();
    // Nothing is picked for staff: the last day must be chosen.
    await expect(sheet.getByTestId("member-benefit-submit")).toBeDisabled();
    await sheet.getByTestId("member-benefit-end-week").click();
    await sheet.getByLabel("Reason (optional, only staff see it)").fill("Lost his job this month");
    await sheet.getByTestId("member-benefit-submit").click();

    await expect(sheet).toBeHidden();
    expect(calls[0].body).toMatchObject({ kind: "grace", reason: "Lost his job this month" });
    expect(String(calls[0].body.idempotency_key).length).toBeGreaterThan(8);
    await expect(card.getByText(/^Grace until/)).toBeVisible();
    await expect(card.getByText(/By Olga/)).toBeVisible();
    await expect(card.getByText("Reason: Lost his job this month")).toBeVisible();

    await card.getByRole("button", { name: "Revoke", exact: true }).click();
    await card.getByLabel("Reason for revoking (optional)").fill("Paid at the desk");
    await card.getByRole("button", { name: "Revoke now" }).click();
    await expect(card.getByText(/Revoked by Olga/)).toBeVisible();
    expect(calls[1]).toMatchObject({ path: "/api/org/box1/admin/finance/members/u-2/benefits/b-1/revoke", body: { reason: "Paid at the desk" } });
  });
});
