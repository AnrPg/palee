import { personProfile } from "./support/profile";
import { expect, test, type Page } from "./support/test";

// ADR-142 (P2-M2): follow requests with the one-time booking-sharing offer
// (board 5 Q6), the connections screen and a person's profile. The API is
// stubbed; every route not listed answers an empty object.

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
const since = new Date().toISOString();
const nikos = { id: "person-2", nickname: "Nikos", avatar_url: null };

// ADR-231: the «Media» grid holds only posts with photos or a video.
const mediaPost = (id: string, body: string, media: Record<string, unknown>[]) => ({
  id,
  origin: "profile",
  audience: "public",
  author: nikos,
  body,
  media: media.map((item, index) => ({ id: `${id}-m${index}`, status: "ready", thumb_url: "/icon.svg", feed_url: "/icon.svg", width: 1080, height: 1080, ...item })),
  media_status: "ready",
  kudos_count: 2,
  comment_count: 0,
  kudos_by_me: false,
  can_delete: false,
  inserted_at: since,
});
const nikosMedia = [
  mediaPost("post-video", "Muscle-ups at last", [{ kind: "video", duration_ms: 42_000, video_url: "/video.mp4", alt_text: null }]),
  mediaPost("post-album", "Open gym Saturday", [
    { kind: "image", alt_text: "Rings" },
    { kind: "image", alt_text: "Rower" },
  ]),
];

async function stub(page: Page) {
  const state = { followers: 0, requests: 1, sharing: { enabled: false, offered: false }, puts: [] as unknown[] };
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) =>
    route.fulfill(json([{ role: "member", roles: ["member"], status: "active", organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli" }, settings: {} }])),
  );
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route("**/api/me/social", (route) =>
    route.fulfill(
      json({
        posts_count: 3,
        followers_count: state.followers,
        following_count: 2,
        requests_count: state.requests,
        booking_sharing: state.sharing,
        follow_groups: { buddies: 0, followers_only: state.followers, following_only: 1 },
      }),
    ),
  );
  await page.route("**/api/me/social/booking-sharing", (route) => {
    const body = route.request().postDataJSON() as { enabled: boolean };
    state.puts.push(body);
    state.sharing = { enabled: body.enabled, offered: true };
    return route.fulfill(json(state.sharing));
  });
  await page.route("**/api/me/follow-requests", (route) =>
    route.fulfill(
      json({ entries: state.requests ? [{ follow_id: "follow-1", status: "requested", since, person: { ...nikos, my_status: "none" } }] : [], next_cursor: null }),
    ),
  );
  await page.route("**/api/me/follow-requests/follow-1/accept", (route) => {
    state.requests = 0;
    state.followers = 1;
    return route.fulfill({ status: 204, body: "" });
  });
  await page.route("**/api/me/followers**", (route) => {
    // The API matches names (board 5 Q4); this stub knows only Nikos.
    const q = new URL(route.request().url()).searchParams.get("q") ?? "";
    const entries = "nikos".includes(q.toLowerCase())
      ? [{ follow_id: "follow-1", status: "active", since, person: { ...nikos, my_status: "none" } }]
      : [];
    return route.fulfill(json({ entries, next_cursor: null }));
  });
  await page.route("**/api/me/following**", (route) =>
    route.fulfill(json({ entries: [{ follow_id: "follow-2", status: "active", since, person: { id: "person-3", nickname: "Eleni", avatar_url: null, my_status: "active" } }], next_cursor: null })),
  );
  await page.route("**/api/people/person-2", (route) =>
    // ADR-554: Nikos added the PRs tab to his profile.
    route.fulfill(json(personProfile({ ...nikos, followers_count: 10, following_count: 4, follows_me: true, tabs: ["media", "posts", "prs"] }))),
  );
  await page.route("**/api/people/person-2/posts**", (route) => route.fulfill(json({ posts: [], next_cursor: null })));
  await page.route("**/api/people/person-2/media**", (route) => route.fulfill(json({ posts: nikosMedia, next_cursor: null })));
  await page.route("**/api/pr-sharing/shared-with-me", (route) => route.fulfill(json({ shared: [] })));
  await page.route("**/api/me/follows/user/person-2", (route) => route.fulfill(json({ status: "none" })));
  return state;
}

test.describe("social", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("accepting the first follower offers booking sharing once", async ({ page }) => {
    const state = await stub(page);
    await page.goto("/me/follow-requests");
    await expect(page.getByText("Nikos")).toBeVisible();
    await expect(page.getByText("Let your followers see which classes you go to?")).toHaveCount(0);

    await page.getByRole("button", { name: "Accept" }).click();
    await expect(page.getByText("Let your followers see which classes you go to?")).toBeVisible();
    await page.getByRole("button", { name: "Yes, let them see" }).click();
    await expect.poll(() => state.puts).toEqual([{ enabled: true }]);
    await expect(page.getByText("Let your followers see which classes you go to?")).toHaveCount(0);
  });

  test("connections list followers and the people you follow in tabs", async ({ page }) => {
    const state = await stub(page);
    state.followers = 1;
    state.requests = 0;
    await page.route("**/api/me/buddies-list**", (route) => route.fulfill(json({ entries: [], next_cursor: null })));
    await page.goto("/me/connections?tab=followers");
    // Six tabs: one row, a full grid or a dropdown, whichever fits (SegmentPicker).
    const pickTab = async (value: string, label: RegExp) => {
      const dropdown = page.getByRole("combobox", { name: "Connections" });
      if (await dropdown.count()) {
        await dropdown.click();
        await page.getByRole("option", { name: label }).click();
      } else {
        await page.getByRole("tablist", { name: "Connections" }).locator(`[data-segment="${value}"]`).click();
      }
    };
    await expect(page.getByRole("tablist", { name: "Connections" }).or(page.getByRole("combobox", { name: "Connections" }))).toContainText(
      "Follow you 1",
    );
    await expect(page.getByRole("link", { name: /Nikos/ })).toHaveAttribute("href", "/people/person-2");
    await page.getByRole("searchbox", { name: "Search people" }).fill("maria");
    await expect(page.getByText("Nothing matches that search.")).toBeVisible();
    await page.getByRole("searchbox", { name: "Search people" }).fill("NIK");
    await expect(page.getByRole("link", { name: /Nikos/ })).toBeVisible();
    await pickTab("following", /^You follow 1/);
    await expect(page).toHaveURL(/tab=following/);
    await expect(page.getByRole("link", { name: /Eleni/ })).toBeVisible();
  });

  test("a person's profile offers follow back and keeps followers posts locked", async ({ page }) => {
    await stub(page);
    await page.goto("/people/person-2");
    await expect(page.getByRole("heading", { name: "Nikos" })).toBeVisible();
    await expect(page.getByText("Follows you")).toBeVisible();
    await expect(page.getByRole("button", { name: "Follow back" })).toBeVisible();
    await expect(page.getByText("Follow to also see followers-only posts.")).toBeVisible();
    // The PRs tab he added: not following yet, so it says what stays hidden.
    await page.getByRole("tab", { name: "PRs" }).click();
    await expect(page.getByRole("tab", { name: "PRs" })).toHaveAttribute("aria-selected", "true");
    await expect(page.getByRole("tabpanel").getByText("Follow to also see followers-only posts.")).toBeVisible();
    // Only the owner adds tabs.
    await expect(page.getByTestId("profile-add-tab")).toHaveCount(0);
    await expect(page.getByTestId("me-sheet-button")).toHaveCount(0);
  });

  test("a person's Media tab is an Instagram-like grid that opens each post", async ({ page }) => {
    await stub(page);
    await page.goto("/people/person-2");
    // ADR-554: Media is the first tab and opens by default.
    await expect(page.getByRole("tab", { name: "Media" })).toHaveAttribute("aria-selected", "true");
    await page.getByRole("tab", { name: "Posts" }).click();
    await expect(page).toHaveURL(/tab=posts/);
    await page.getByRole("tab", { name: "Media" }).click();
    await expect(page).toHaveURL(/tab=media/);
    const grid = page.getByTestId("media-grid");
    await expect(grid.getByRole("button")).toHaveCount(2);
    await expect(grid.getByRole("button", { name: "Video 0:42" })).toBeVisible();
    await expect(grid.getByRole("button", { name: "2 photos: Rings" })).toBeVisible();
    // Not following yet: the grid says what stays hidden, like the posts.
    await expect(page.getByText("Follow to also see followers-only posts.")).toBeVisible();
    await page.screenshot({ path: "test-results/social/person-media.png", fullPage: true });

    await grid.getByRole("button", { name: "2 photos: Rings" }).click();
    const dialog = page.getByRole("dialog", { name: "Nikos's post" });
    await expect(dialog.getByText("Open gym Saturday")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(dialog).toHaveCount(0);

    // A deep link opens the tab directly.
    await page.goto("/people/person-2?tab=media");
    await expect(page.getByRole("tab", { name: "Media" })).toHaveAttribute("aria-selected", "true");
  });

  test("a person's tabs are Media · Posts plus the ones they added, with no counts and no Clubs tab", async ({ page }) => {
    await stub(page);
    await page.goto("/people/person-2");
    const tabs = page.getByRole("tablist", { name: "Profile" }).getByRole("tab");
    await expect(tabs).toHaveCount(3);
    await expect(tabs.nth(0)).toHaveAccessibleName("Media");
    await expect(tabs.nth(1)).toHaveAccessibleName("Posts");
    await expect(tabs.nth(2)).toHaveAccessibleName("PRs");
    await expect(tabs.nth(0)).toHaveAttribute("aria-selected", "true");
    await expect(tabs.nth(1)).toHaveAttribute("aria-selected", "false");
    await expect(tabs.nth(0)).toHaveText("Media");
    await expect(page.getByRole("tab", { name: "Clubs" })).toHaveCount(0);
    // An unknown or hidden ?tab= falls back to Media.
    await page.goto("/people/person-2?tab=badges");
    await expect(page.getByRole("tab", { name: "Media" })).toHaveAttribute("aria-selected", "true");
    await expect(page.getByRole("tab", { name: "Badges" })).toHaveCount(0);
  });

  test("a followed person's box · belt line and their Workouts and Progress tabs (ADR-554)", async ({ page }) => {
    await stub(page);
    await page.route("**/api/people/person-2", (route) =>
      route.fulfill(
        json(
          personProfile({
            ...nikos,
            my_status: "active",
            tabs: ["media", "posts", "workouts", "progress"],
            box: { slug: "box-kypseli", name: "Box Kypseli", rank: { name: "Purple", color: "purple", style: "belt", stripes: 2 } },
          }),
        ),
      ),
    );
    await page.route("**/api/people/person-2/workouts", (route) =>
      route.fulfill(
        json({
          locked: false,
          workouts: [{ id: "w-1", title: "Murph", completed_at: "2026-11-07T08:30:00Z", completed_tz: "Europe/Athens", elapsed_ms: 2_900_000 }],
        }),
      ),
    );
    await page.route("**/api/people/person-2/progress", (route) =>
      route.fulfill(json({ locked: false, progress: { total_workouts: 42, current_streak: 1, longest_streak: 9, total_prs: 5 } })),
    );
    await page.goto("/people/person-2");

    const line = page.getByTestId("profile-box");
    await expect(line.getByRole("link", { name: "Box Kypseli" })).toHaveAttribute("href", "/b/box-kypseli");
    await expect(line).toContainText("Purple · 2 stripes");

    await page.getByRole("tab", { name: "Workouts" }).click();
    await expect(page).toHaveURL(/\?tab=workouts$/);
    await expect(page.getByTestId("profile-workouts")).toContainText("Murph");
    await expect(page.getByTestId("profile-workouts")).toContainText("48:20");

    await page.getByRole("tab", { name: "Progress" }).click();
    const progress = page.getByTestId("profile-progress");
    await expect(progress).toContainText("42");
    await expect(progress).toContainText("workouts");
    await expect(progress).toContainText("day in a row now");
    await expect(progress).toContainText("days, longest streak");
  });

  test("Εγώ is my own profile: handle, counts, Media first, the ☰, a tab added with + and a bio (ADR-554)", async ({ page }) => {
    await stub(page);
    const card: { bio: string | null; tabs: string[] } = { bio: null, tabs: ["media", "posts"] };
    const cardPuts: unknown[] = [];
    await page.route("**/api/people/member-1", (route) =>
      route.fulfill(
        json(
          personProfile({
            id: user.id,
            nickname: user.nickname,
            handle: "maria.l",
            is_me: true,
            followers_count: 7,
            following_count: 5,
            follow_groups: { buddies: 2, followers_only: 5, following_only: 3 },
            ...card,
          }),
        ),
      ),
    );
    await page.route("**/api/people/member-1/media**", (route) => route.fulfill(json({ posts: [], next_cursor: null })));
    await page.route("**/api/people/member-1/posts**", (route) => route.fulfill(json({ posts: [], next_cursor: null })));
    await page.route("**/api/people/member-1/badges", (route) =>
      route.fulfill(json({ badges: [{ id: "badge-1", badge_key: "workouts_10", label: "10 workouts", earned_at: "2026-10-01T10:00:00Z" }], locked: false })),
    );
    await page.route("**/api/me/profile-card", (route) => {
      if (route.request().method() !== "PUT") return route.fallback();
      const body = route.request().postDataJSON() as { bio?: string | null; tabs?: string[] };
      cardPuts.push(body);
      if (body.tabs) card.tabs = ["media", "posts", ...body.tabs];
      if ("bio" in body) card.bio = body.bio ?? null;
      return route.fulfill(json(card));
    });

    await page.goto("/me");
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("maria.l");
    const counts = page.getByRole("list", { name: "Buddies and follows" });
    await expect(counts.getByRole("listitem")).toHaveText([/2\s*Buddies/, /5\s*Follow you/, /3\s*You follow/]);
    await expect(counts.getByRole("link").first()).toHaveAttribute("href", "/me/connections?tab=buddies");
    await expect(page.getByRole("tab", { name: "Media" })).toHaveAttribute("aria-selected", "true");
    await expect(page.getByRole("tab", { name: "Badges" })).toHaveCount(0);

    // ☰ «Only for you»: what I do rather than show.
    await page.getByTestId("me-sheet-button").click();
    const sheet = page.getByTestId("me-sheet");
    await expect(sheet).toHaveAccessibleName("Only for you");
    await expect(sheet.getByRole("link", { name: /^Settings/ })).toHaveAttribute("href", "/me/settings");
    await page.keyboard.press("Escape");
    await expect(sheet).toHaveCount(0);

    // «+» adds the Badges tab, last.
    await page.getByTestId("profile-add-tab").click();
    const addTab = page.getByTestId("add-tab-dialog");
    await expect(addTab.getByRole("switch", { name: /^PRs/ })).not.toBeChecked();
    // The switch follows the saved card, so it turns on once the PUT answers.
    await addTab.getByRole("switch", { name: /^Badges/ }).click();
    await expect.poll(() => cardPuts).toEqual([{ tabs: ["badges"] }]);
    await expect(addTab.getByRole("switch", { name: /^Badges/ })).toBeChecked();
    await page.keyboard.press("Escape");
    await expect(addTab).toHaveCount(0);
    await expect(page.getByRole("tablist", { name: "Profile" }).getByRole("tab").last()).toHaveAccessibleName("Badges");
    await page.getByRole("tab", { name: "Badges" }).click();
    await expect(page.getByTestId("profile-badges")).toContainText("Completed 10 workouts");

    // Edit profile saves «Bio», which then shows under the header.
    await expect(page.getByTestId("profile-bio")).toHaveCount(0);
    await page.getByRole("button", { name: "Edit profile" }).click();
    const edit = page.getByTestId("edit-profile-dialog");
    await edit.getByRole("textbox", { name: "Bio" }).fill("Lifting at dawn.");
    await edit.getByRole("button", { name: "Save" }).click();
    await expect(edit).toHaveCount(0);
    expect(cardPuts.at(-1)).toEqual({ bio: "Lifting at dawn." });
    await expect(page.getByTestId("profile-bio")).toHaveText("Lifting at dawn.");
    await page.screenshot({ path: "test-results/social/me-profile.png", fullPage: true });
  });
});

// ANR 2026-11-07: on a narrow phone the unfollow confirm («Άκυρο / Άρση
// ακολούθησης») ran off the screen. In Greek, the longest labels, at 320px.
test.describe("social on a narrow phone", () => {
  test.use({ viewport: { width: 320, height: 640 } });

  test("the unfollow confirm drops under the name and stays on screen", async ({ page }) => {
    const state = await stub(page);
    state.requests = 0;
    await page.context().addCookies([{ name: "palee_locale", value: "el", url: "http://127.0.0.1" }]);
    // The signed-in person's own language wins over the cookie.
    await page.route("**/api/auth/me", (route) => route.fulfill(json({ ...user, preferred_locale: "el" })));
    await page.route("**/api/me/buddies-list**", (route) => route.fulfill(json({ entries: [], next_cursor: null })));
    await page.route("**/api/me/follows/user/person-3", (route) => route.fulfill(json({ status: "active" })));
    await page.goto("/me/connections?tab=following");
    const row = page.getByRole("listitem").filter({ has: page.getByRole("link", { name: /Eleni/ }) });
    await row.getByRole("button", { name: "Ακολουθείς" }).click();

    const confirm = row.getByRole("group", { name: /Να σταματήσεις να ακολουθείς/ });
    await expect(confirm).toBeVisible();
    await expect(row.getByRole("link", { name: /Eleni/ })).toBeVisible();
    for (const name of ["Άκυρο", "Άρση ακολούθησης"]) {
      const box = await confirm.getByRole("button", { name }).boundingBox();
      expect(box, name).not.toBeNull();
      expect(box!.x).toBeGreaterThanOrEqual(0);
      expect(box!.x + box!.width).toBeLessThanOrEqual(320);
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(320);

    await confirm.getByRole("button", { name: "Άκυρο" }).click();
    await expect(confirm).toHaveCount(0);
    await expect(row.getByRole("button", { name: "Ακολουθείς" })).toBeVisible();
  });
});
