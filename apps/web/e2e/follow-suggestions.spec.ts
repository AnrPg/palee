import { expect, test, type Page } from "./support/test";

// ADR-561 (ANR's picks 2026-11-09): «People you may know» on Home with one
// reason per person, ✕ with undo, ⋯ «Hide suggestions», and the whole list
// in Find while its field is empty. The API is stubbed; every route not
// listed answers an empty object.

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

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const suggestions = [
  {
    id: "person-1",
    nickname: "Eleni",
    handle: "eleni",
    avatar_url: null,
    private: false,
    reason: { kind: "box", box: { id: "org-1", name: "Box Kypseli" }, mutual_count: 0, mutuals: [] },
  },
  {
    id: "person-2",
    nickname: "Kostas",
    handle: "kostas",
    avatar_url: null,
    private: false,
    reason: { kind: "mutual", mutual_count: 3, mutuals: [{ id: "person-5", nickname: "Nikos" }, { id: "person-6", nickname: "Anna" }] },
  },
];

const match = {
  id: "match-1",
  status: "active",
  matched_at: new Date().toISOString(),
  last_message_at: null,
  unread: 0,
  person: { id: "person-9", nickname: "Eleni", avatar_url: null },
};

async function stub(page: Page, { partners = false }: { partners?: boolean } = {}) {
  const calls = { followed: [] as unknown[], dismissed: [] as string[], privacy: [] as unknown[] };
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(json([{ role: "member", roles: ["member"], status: "active", organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" }, settings: {} }])),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/threads**", (route) => route.fulfill(json({ threads: [] })));
  await page.route("**/api/me/conversations**", (route) => route.fulfill(json({ entries: [], next_cursor: null, count: 0 })));
  await page.route("**/api/me/partners/matches", (route) => route.fulfill(json({ matches: partners ? [match] : [] })));
  await page.route("**/api/pr-sharing", (route) => route.fulfill(json({ grants: [] })));
  await page.route("**/api/prs", (route) => route.fulfill(json({ prs: [] })));
  await page.route("**/api/me/buddies", (route) => route.fulfill(json({ buddies: [], supporting: [], invitations: [] })));
  // No settings stored yet: the account reads as public and searchable.
  await page.route("**/api/me/social", (route) =>
    route.fulfill(
      json({
        posts_count: 0,
        followers_count: 0,
        following_count: 0,
        requests_count: 0,
        booking_sharing: { enabled: false, offered: false },
        privacy: { private_account: false, searchable: true, show_follow_suggestions: true },
        follow_groups: { buddies: 0, followers_only: 0, following_only: 0 },
      }),
    ),
  );
  // Each card's button reads its own follow status; a follow sticks, as on the
  // server, so the refetch after it (the whole social cache) still says so.
  const following = new Set<string>();
  await page.route("**/api/me/follows/user/*", (route) => {
    const id = new URL(route.request().url()).pathname.split("/").pop()!;
    return route.fulfill(json({ status: following.has(id) ? "active" : "none" }));
  });
  await page.route("**/api/me/follow-suggestions?**", (route) => route.fulfill(json({ people: suggestions })));
  await page.route("**/api/me/follow-suggestions", (route) => route.fulfill(json({ people: suggestions })));
  await page.route("**/api/me/follow-suggestions/*/follow", (route) => {
    calls.followed.push(route.request().postDataJSON());
    following.add(new URL(route.request().url()).pathname.split("/").at(-2)!);
    return route.fulfill(json({ status: "active" }));
  });
  await page.route("**/api/me/follow-suggestions/*/dismiss", (route) => {
    calls.dismissed.push(route.request().method());
    return route.fulfill({ status: 204, body: "" });
  });
  await page.route("**/api/me/social/privacy", (route) => {
    calls.privacy.push(route.request().postDataJSON());
    return route.fulfill(json({ private_account: false, searchable: true, show_follow_suggestions: false }));
  });
  return calls;
}

test("Home suggests people with a reason; follow, ✕ with undo and hide", async ({ page }) => {
  const calls = await stub(page);
  await page.goto("/");
  // A member of one box opens on the Box tab (W7 screen 12); Feed is one tap away.
  await expect(page).toHaveURL(/\/box$/);
  await page.getByRole("link", { name: "Feed", exact: true }).first().click();
  await expect(page).toHaveURL(/\/$/);

  const card = page.locator('[data-follow-suggestions="home"]');
  await expect(card.getByRole("heading", { name: "People you may know" })).toBeVisible();
  await expect(card.getByText("At Box Kypseli")).toBeVisible();
  await expect(card.getByText("Mutual: Nikos, Anna and 1 more")).toBeVisible();

  await card.locator('[data-suggestion="person-1"]').getByRole("button", { name: "Follow" }).click();
  await expect(card.locator('[data-suggestion="person-1"]').getByRole("button", { name: /Following/ })).toBeVisible();
  expect(calls.followed).toEqual([{ reason: "box" }]);

  await card.getByRole("button", { name: "Remove Kostas from suggestions" }).click();
  await expect(card.getByText("Won't be suggested again.")).toBeVisible();
  await card.getByRole("button", { name: "Undo" }).click();
  await expect(card.getByText("Mutual: Nikos, Anna and 1 more")).toBeVisible();
  expect(calls.dismissed).toEqual(["POST", "DELETE"]);

  await card.getByRole("button", { name: "More" }).click();
  await page.getByRole("menuitem", { name: "Hide suggestions" }).click();
  await expect(card).toHaveCount(0);
  expect(calls.privacy).toEqual([{ show_follow_suggestions: false }]);
});

test("Find lists the suggestions while nothing is typed", async ({ page }) => {
  await stub(page);
  await page.goto("/clubs/find");
  const list = page.locator('[data-follow-suggestions="find"]');
  await expect(list.getByRole("heading", { name: "Suggested for you" })).toBeVisible();
  await expect(list.getByText("Eleni")).toBeVisible();
  await page.getByRole("searchbox").first().fill("el");
  await expect(list).toHaveCount(0);
});
