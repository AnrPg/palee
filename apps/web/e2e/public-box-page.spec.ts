import { createServer, type Server } from "node:http";

import { expect, test, type Page } from "./support/test";

import { stubApiPort } from "../playwright.config";

import { chooseOption } from "./support/select";

// The public box page (ADR-142, plan §5a board 4, board 5 Q1–Q2). The page is
// server-rendered, so its read goes to a stub API on `stubApiPort`; what the
// browser fetches afterwards is stubbed with page.route.

const pixel = (color: string) =>
  `data:image/svg+xml;utf8,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630"><rect width="100%" height="100%" fill="${color}"/></svg>`)}`;

const box = { organization_id: "org-1", slug: "crossfit-kypseli", name: "CrossFit Kypseli", logo_url: null, primary_color: "#D9743D" };

const publicBox = {
  box,
  followers_count: 12,
  joining: { packages: false, join_link: false },
  profile: {
    about: "A friendly box in Kypseli.\nCoaches who know your name.",
    disciplines: ["crossfit", "olympic_lifting", "yoga", "pilates", "hyrox", "gymnastics", "running", "mobility"],
    audiences: ["beginners", "over_40"],
    services: ["personal_training", "open_gym"],
    amenities: ["showers", "towels", "wifi"],
    languages: ["el", "en"],
    cover: { id: "cover", url: pixel("#7a3b1d"), width: 1200, height: 630 },
    photos: [
      { id: "p1", url: pixel("#335577"), width: 1200, height: 630 },
      { id: "p2", url: pixel("#557733"), width: 1200, height: 630 },
    ],
    coaches: [{ id: "coach-1", nickname: "Stelios", avatar_url: null, class_types: ["CrossFit", "Olympic lifting"] }],
  },
  locations: [
    {
      id: "loc-1",
      name: "Kypseli",
      address: "Fokionos Negri 10",
      neighbourhood: "Kypseli",
      city: "Athens",
      country_code: "GR",
      latitude: 38.0035,
      longitude: 23.7369,
      accessibility: [],
      opening_hours: [1, 2, 3, 4, 5, 6, 7].map((weekday) => ({ weekday, opens: "07:00", closes: "22:00" })),
    },
  ],
};

const joinVariants: Record<string, { packages: boolean; join_link: boolean }> = {
  "kypseli-packages": { packages: true, join_link: false },
  "kypseli-link": { packages: false, join_link: true },
};

let server: Server;

test.beforeAll(async () => {
  server = createServer((request, response) => {
    const match = request.url?.match(/^\/api\/public\/boxes\/([^/?]+)/);
    if (match && (match[1] === box.slug || match[1] === "kypseli-old")) {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify(publicBox));
      return;
    }
    // ANR 2026-11-07: where «Become a box member» leads, per box.
    const joining = match ? joinVariants[match[1]] : undefined;
    if (joining) {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({ ...publicBox, box: { ...box, slug: match![1] }, joining }));
      return;
    }
    response.writeHead(404, { "content-type": "application/json" });
    response.end(JSON.stringify({ error: "not_found" }));
  });
  await new Promise<void>((resolve) => server.listen(stubApiPort, "127.0.0.1", resolve));
});

test.afterAll(async () => {
  await new Promise((resolve) => server.close(resolve));
});

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

const user = {
  id: "member-1",
  nickname: "Maria L",
  role: "member",
  email: "member-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [] as { organization_slug: string; role: string; settings: object }[],
};

function token() {
  const payload = Buffer.from(JSON.stringify({ sub: user.id, role: user.role, memberships: [], exp: Math.floor(Date.now() / 1000) + 3600 })).toString("base64url");
  return `stub.${payload}.signature`;
}

function todayAt(hour: number) {
  const date = new Date();
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

async function asGuest(page: Page) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
}

async function signedIn(page: Page, { member = false } = {}) {
  const follows: unknown[] = [];
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token(), refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json({ memberships: [] })));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) =>
    route.fulfill(
      json({
        clubs: member
          ? [{ id: "club-1", kind: "gym", name: box.name, organization_id: box.organization_id, organization_slug: box.slug, box_page: true, role: "member", notify_level: "all", logo_url: null, primary_color: null, channels: [] }]
          : [],
      }),
    ),
  );
  await page.route("**/api/me/follows/organization/org-1", (route) => route.fulfill(json({ status: follows.length ? "active" : "none" })));
  await page.route("**/api/me/follows", (route) => {
    follows.push(route.request().postDataJSON());
    return route.fulfill(json({ status: "active" }));
  });
  await page.route(`**/api/boxes/${box.slug}/schedule**`, (route) =>
    route.fulfill(
      json({
        box,
        start_at: todayAt(0),
        end_at: todayAt(23),
        slots: [
          {
            id: "slot-1",
            name: "CrossFit",
            scheduled_at: todayAt(23),
            duration_minutes: 60,
            capacity: 12,
            spots_remaining: 4,
            location_id: "loc-1",
            coach: { id: "coach-1", nickname: "Stelios", avatar_url: null },
            class_type: { id: "type-1", name: "CrossFit", levels: ["intermediate", "advanced"], audiences: [] },
          },
          {
            id: "slot-2",
            name: "Yoga 40+",
            scheduled_at: todayAt(23),
            duration_minutes: 45,
            capacity: 10,
            spots_remaining: 0,
            location_id: "loc-1",
            coach: null,
            class_type: { id: "type-2", name: "Yoga", levels: ["beginner"], audiences: ["over_40"] },
          },
        ],
      }),
    ),
  );
  await page.route(`**/api/boxes/${box.slug}/posts**`, (route) => route.fulfill(json({ box, posts: [], next_cursor: null })));
  return follows;
}

test.describe("public box page", () => {
  test("logged out: Σχετικά is open, the other tabs ask to sign in, and previews carry the name", async ({ page }) => {
    await asGuest(page);
    await page.goto(`/b/${box.slug}`);

    await expect(page.getByRole("heading", { name: box.name }).first()).toBeVisible();
    await expect(page).toHaveTitle(/CrossFit Kypseli/);
    await expect(page.locator('meta[property="og:title"]')).toHaveAttribute("content", box.name);
    await expect(page.getByText("A friendly box in Kypseli.")).toBeVisible();
    await expect(page.getByText("Ελληνικά · English")).toBeVisible();
    await expect(page.getByText("Stelios")).toBeVisible();
    await expect(page.getByRole("button", { name: "2 more disciplines" })).toBeVisible();
    if ((page.viewportSize()?.width ?? 0) >= 1024) {
      // Desktop (board 5 Q1): the side card's map opens the location in Maps.
      await expect(page.getByRole("link", { name: "Open in Maps" })).toHaveAttribute(
        "href",
        "https://www.google.com/maps/search/?api=1&query=38.0035,23.7369",
      );
    }

    await page.getByRole("tab", { name: "Schedule" }).click();
    await expect(page).toHaveURL(/#schedule$/);
    await expect(page.getByText("Sign in to see the schedule")).toBeVisible();
    await expect(page.getByRole("link", { name: "Sign in" })).toHaveAttribute("href", `/login?next=${encodeURIComponent(`/b/${box.slug}#schedule`)}`);
  });

  test("a retired slug redirects to the canonical page", async ({ page }) => {
    await asGuest(page);
    await page.goto("/b/kypseli-old");
    await expect(page).toHaveURL(new RegExp(`/b/${box.slug}$`));
  });

  test("photos open full screen with a counter", async ({ page }) => {
    await asGuest(page);
    await page.goto(`/b/${box.slug}`);
    await page.getByRole("button", { name: "Photo 2" }).click();
    const viewer = page.getByRole("dialog", { name: "Photos" });
    await expect(viewer.getByText("3 of 3")).toBeVisible();
    await viewer.getByRole("button", { name: "Close" }).click();
    await expect(viewer).toBeHidden();
  });

  test("signed in: the schedule lists classes with filters and a sheet, and the box can be followed", async ({ page, isMobile }) => {
    const follows = await signedIn(page);
    await page.goto(`/b/${box.slug}#schedule`);

    await expect(page.getByRole("button", { name: /Yoga 40\+/ })).toBeVisible();
    // ADR-621: desktop shows the week in seven columns with the filters in its row; phones fold them away.
    if (!isMobile) await expect(page.getByTestId("schedule-week-grid").getByRole("listitem")).toHaveCount(7);
    else await page.getByRole("button", { name: "Filters", exact: true }).click();
    await chooseOption(page, page.getByLabel("Level"), "beginner");
    await expect(page.getByRole("button", { name: /CrossFit.*Stelios/ })).toBeHidden();
    await page.getByRole("button", { name: /Yoga 40\+/ }).click();
    const sheet = page.getByRole("dialog", { name: "Yoga 40+" });
    // Trials are off at this box: no trial action on the class.
    await expect(sheet.getByRole("button", { name: "Book as a trial" })).toBeHidden();
    // The header × and the footer button both close it.
    await sheet.getByRole("button", { name: "Close" }).first().click();

    await page.getByRole("button", { name: "Follow" }).first().click();
    await expect.poll(() => follows).toEqual([{ target_type: "organization", target_id: "org-1" }]);
  });

  test("a member of the gym lands on the «Club» tab, first, instead of following (ADR-590)", async ({ page }) => {
    await signedIn(page, { member: true });
    await page.route("**/api/org/*/community/wod-today**", (route) =>
      route.fulfill(json({ date: "2026-10-20", channel_id: null, classes: [], leaderboard: [], logged_by_me: false, score: null, workout: null })),
    );
    await page.route("**/api/me/feed**", (route) => route.fulfill(json({ posts: [], pinned: [], next_cursor: null })));
    await page.goto(`/b/${box.slug}`);
    const tabs = page.getByRole("tablist", { name: "Page sections" });
    await expect(tabs.getByRole("tab").first()).toHaveText("Club");
    // Scoped to the page's own tabs: the club inside has a «Club members» tab too.
    await expect(tabs.getByRole("tab", { name: "Club", exact: true })).toHaveAttribute("aria-selected", "true");
    await expect(page.getByTestId("box-club-tab")).toBeVisible();
    await expect(page.getByTestId("box-guest-banner")).toHaveCount(0);
    await expect(page.getByTestId("box-page-join")).toHaveCount(0);

    // ADR-621: one level of navigation, «Write something to the club…» over the feed,
    // no «Club member» line, and no filters over an empty club.
    const club = page.getByTestId("box-club-tab");
    await expect(club.getByTestId("club-compose-prompt")).toHaveText("Write something to the club…");
    await expect(club.getByText("Club member", { exact: true })).toHaveCount(0);
    await expect(club.getByRole("button", { name: "Filters", exact: true })).toHaveCount(0);
    await expect(club.getByRole("tab", { name: "Events" })).toHaveCount(0);
    await expect(page.getByTestId("box-page-role")).toHaveText("Box member");

    // Members message the box from the header; the club is a tab, so no «Open the club» pill.
    await page.getByRole("tab", { name: "About" }).click();
    await expect(page).toHaveURL(/#about$/);
    await expect(page.getByTestId("box-page-message").locator("visible=true").first()).toHaveText("Message");
    await expect(page.getByText("Box member · Open the club")).toHaveCount(0);
    await tabs.getByRole("tab", { name: "Club", exact: true }).click();
    await expect(page.getByTestId("box-club-tab")).toBeVisible();

    // One «Events» tab: members see the club's events there.
    await tabs.getByRole("tab", { name: "Events" }).click();
    await expect(page.getByText("No upcoming events.")).toBeVisible();
  });

  test("a box's club link opens the box page when it is published (ADR-590)", async ({ page }) => {
    await signedIn(page, { member: true });
    await page.goto("/clubs/club-1?channel=ch-1");
    await expect(page).toHaveURL(new RegExp(`/b/${box.slug}\\?channel=ch-1$`));
  });

  test("a visitor never sees the «Club» tab", async ({ page }) => {
    await signedIn(page);
    await page.goto(`/b/${box.slug}#club`);
    await expect(page.getByRole("tab", { name: "Club", exact: true })).toHaveCount(0);
    await expect(page.getByRole("tab", { name: "About" })).toHaveAttribute("aria-selected", "true");
  });

  test("«Become a box member» is always the main action and never a dead end", async ({ page }) => {
    await asGuest(page);
    await page.goto(`/b/${box.slug}`);
    // No packages and no open join link: a request to the box, after signing in.
    const join = page.getByTestId("box-page-join").first();
    await expect(join).toHaveText("Become a box member");
    await expect(join).toHaveAttribute("href", `/login?next=${encodeURIComponent(`/b/${box.slug}?join=1`)}`);

    await page.goto("/b/kypseli-packages");
    await expect(page.getByTestId("box-page-join").first()).toHaveAttribute("href", "/b/kypseli-packages/packages");

    await page.goto("/b/kypseli-link");
    await expect(page.getByTestId("box-page-join").first()).toHaveAttribute("href", "/join/kypseli-link");
  });

  test("signed in, without packages or a join link, «Become a box member» asks the box to accept you", async ({ page }) => {
    await signedIn(page);
    let status: string | null = null;
    const asked: string[] = [];
    const mine = () =>
      status ? { id: "jr-1", status, requested_at: "2026-11-07T10:00:00Z", decided_at: null, box: { slug: box.slug, name: box.name } } : null;
    await page.route(`**/api/boxes/${box.slug}/join-request`, (route) => {
      if (route.request().method() === "POST") {
        asked.push("ask");
        status = "requested";
        return route.fulfill(json({ request: mine() }, 201));
      }
      return route.fulfill(json({ request: mine() }));
    });
    await page.route(`**/api/boxes/${box.slug}/join-request/cancel`, (route) => {
      status = "cancelled";
      return route.fulfill(json({ request: mine() }));
    });
    await page.goto(`/b/${box.slug}`);
    // The desktop and the phone layouts each hold the action; click the one on screen.
    await page.getByTestId("box-page-join").locator("visible=true").first().click();
    const sheet = page.getByTestId("box-join-ask");
    await sheet.getByTestId("box-join-send").click();
    await expect(sheet.getByTestId("box-join-pending")).toHaveText("Waiting for the box to accept");
    expect(asked).toEqual(["ask"]);
    await sheet.getByRole("button", { name: "Withdraw request" }).click();
    await expect(sheet.getByTestId("box-join-send")).toBeVisible();
  });

  test("coming back from sign-in with ?join=1 opens the request sheet", async ({ page }) => {
    await signedIn(page);
    await page.route(`**/api/boxes/${box.slug}/join-request`, (route) => route.fulfill(json({ request: null })));
    await page.goto(`/b/${box.slug}?join=1`);
    await expect(page.getByTestId("box-join-ask")).toBeVisible();
  });

  test("a guest of the box (ADR-272) sees it, with becoming a box member as the next step", async ({ page }) => {
    await signedIn(page);
    await page.route("**/api/memberships/guest-boxes", (route) =>
      route.fulfill(json({ boxes: [{ id: box.organization_id, name: box.name, slug: box.slug }] })),
    );
    await page.goto(`/b/${box.slug}`);
    const banner = page.getByTestId("box-guest-banner");
    await expect(banner.getByRole("heading", { name: `You're a guest of ${box.name}` })).toBeVisible();
    await expect(banner).toContainText("Become a box member to book classes and see the workouts.");
    await expect(banner.getByRole("link", { name: "Become a box member" })).toHaveAttribute("href", `/b/${box.slug}/packages`);
  });

  test("a follower the box invited (ADR-580) sees the invitation and can say no, thanks", async ({ page }) => {
    await signedIn(page);
    let invite: Record<string, unknown> | null = {
      id: "fi-1",
      status: "sent",
      sent_at: "2026-11-09T10:00:00Z",
      message: "Come and train with us!",
      offer_trial: false,
      package: { id: "p-1", name: "Unlimited", price_cents: 7500, currency: "EUR", billing_period: "monthly" },
      box: { slug: box.slug, name: box.name },
    };
    const declined: string[] = [];
    await page.route(`**/api/boxes/${box.slug}/follower-invite`, (route) => route.fulfill(json({ invite })));
    await page.route(`**/api/boxes/${box.slug}/follower-invite/decline`, (route) => {
      declined.push("decline");
      invite = null;
      return route.fulfill(json({ invite: null }));
    });
    await page.goto(`/b/${box.slug}`);
    const notice = page.getByTestId("box-follower-invite");
    await expect(notice.getByRole("heading", { name: `${box.name} invites you to become a member` })).toBeVisible();
    await expect(notice).toContainText("«Come and train with us!»");
    await expect(notice.getByTestId("box-follower-invite-package")).toContainText("Unlimited");
    // «Become a box member» stays the page's own action (ADR-552). The desktop
    // and the phone layouts each hold it; the one on screen must be visible.
    await expect(page.getByTestId("box-page-join").locator("visible=true").first()).toBeVisible();
    await notice.getByTestId("box-follower-invite-decline").click();
    await expect(notice).toBeHidden();
    expect(declined).toEqual(["decline"]);
  });
});

// ADR-621 (ANR 2026-11-10): the «Club» and «Schedule» tabs on desktop and phones.
// Every control is checked visible and, with a trial click, not covered by the
// sticky bar, the side column or the bottom tab bar before it is used.
const clubChannel = (id: string, kind: string) => ({
  id,
  kind,
  name: null,
  write_policy: "members",
  membership: "everyone",
  joined: true,
  can_post: true,
  can_leave: false,
});

const clubPost = {
  id: "post-1",
  origin: "club",
  audience: "club_channel",
  author: { id: "member-2", nickname: "Eleni", avatar_url: null },
  body: "Who's in for Saturday's partner WOD?",
  attachment: null,
  attachment_id: null,
  attachment_type: null,
  can_delete: false,
  can_moderate: false,
  can_pin: false,
  can_report: true,
  channel: { id: "ch-gen", kind: "general", name: null },
  club: { id: "club-1", name: box.name, organization_slug: box.slug, kind: "gym" },
  comment_count: 0,
  hidden: false,
  inserted_at: new Date().toISOString(),
  kudos_by_me: false,
  kudos_count: 0,
  pinned: false,
};

function clubEvent() {
  const startsAt = new Date(Date.now() + 3 * 86_400_000).toISOString();
  return {
    id: "event-1",
    organization_id: box.organization_id,
    club_id: "club-1",
    club: { id: "club-1", name: box.name, kind: "gym" },
    box: { name: box.name, slug: box.slug, logo_url: null },
    title: "Saturday partner WOD",
    starts_at: startsAt,
    ends_at: startsAt,
    place: { name: box.name, address: null, latitude: null, longitude: null, location_id: null },
    capacity: 20,
    spots_left: 10,
    going_count: 10,
    waitlist_count: 0,
    price_cents: 0,
    currency: "EUR",
    open_to_non_members: false,
    guest_pass_allowed: false,
    guests_per_member: 0,
    goers: null,
    cancelled: false,
    can_rsvp: true,
    can_manage: false,
    my: null,
  };
}

/** A member of a club with two channels, one post, one event and three club members; returns the feed requests. */
async function busyClub(page: Page) {
  await signedIn(page, { member: true });
  const feeds: URL[] = [];
  await page.route("**/api/me/clubs", (route) =>
    route.fulfill(
      json({
        clubs: [
          {
            id: "club-1",
            kind: "gym",
            name: box.name,
            organization_id: box.organization_id,
            organization_slug: box.slug,
            box_page: true,
            role: "member",
            notify_level: "all",
            logo_url: null,
            primary_color: null,
            channels: [clubChannel("ch-gen", "general"), clubChannel("ch-wod", "wod")],
          },
        ],
      }),
    ),
  );
  await page.route("**/api/org/*/community/wod-today**", (route) =>
    route.fulfill(json({ date: "2026-10-20", channel_id: null, classes: [], leaderboard: [], logged_by_me: false, score: null, workout: null })),
  );
  await page.route("**/api/me/feed**", (route) => {
    feeds.push(new URL(route.request().url()));
    return route.fulfill(json({ posts: [clubPost], pinned: [], next_cursor: null }));
  });
  await page.route("**/api/me/community/clubs/club-1/events**", (route) => route.fulfill(json({ events: [clubEvent()] })));
  await page.route("**/api/me/clubs/club-1/members**", (route) =>
    route.fulfill(
      json({
        club_id: "club-1",
        count: 3,
        members: [
          { id: "coach-1", nickname: "Stelios", avatar_url: null, coach: true, following: false },
          { id: "member-2", nickname: "Eleni", avatar_url: null, coach: false, following: true },
          { id: "member-3", nickname: "Petros", avatar_url: null, coach: false, following: false },
        ],
      }),
    ),
  );
  return feeds;
}

/** Visible, and a click would land on it (nothing covers it). */
async function reachable(locator: ReturnType<Page["locator"]>) {
  await expect(locator).toBeVisible();
  await locator.click({ trial: true });
}

test.describe("the «Club» and «Schedule» tabs (ADR-621)", () => {
  test("desktop: the feed with «Write something», and a side column of events, channels and club members", async ({ page, isMobile }) => {
    test.skip(isMobile, "the side column is desktop only");
    const feeds = await busyClub(page);
    await page.goto(`/b/${box.slug}`);

    const club = page.getByTestId("box-club-tab");
    await expect(club.getByText("Who's in for Saturday's partner WOD?")).toBeVisible();
    // No inner tabs on desktop: the side column replaces them.
    await expect(club.getByRole("tablist")).toHaveCount(0);
    const side = page.getByTestId("box-club-side");
    await expect(side).toBeVisible();

    // The header: a low cover, the labelled «Message» and one share button.
    await reachable(page.getByTestId("box-page-message").locator("visible=true").first());
    await expect(page.getByTestId("box-page-message").locator("visible=true").first()).toHaveText("Message");
    await reachable(page.getByTestId("box-page-header-share"));
    await expect(page.getByRole("button", { name: "Share" }).locator("visible=true")).toHaveCount(1);

    // Filters: the coaches filter lives in the sheet only, under its clear name.
    const filters = club.getByRole("button", { name: "Filters", exact: true });
    await reachable(filters);
    await expect(club.getByRole("button", { name: "Posts by coaches" })).toHaveCount(0);
    await expect(club.getByRole("button", { name: "Coaches only" })).toHaveCount(0);
    await filters.click();
    const sheet = page.getByRole("dialog", { name: "Post filters" });
    await expect(sheet.getByRole("button", { name: "Posts by coaches" })).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(sheet).toBeHidden();

    // Events show once, in the side column.
    const events = page.getByTestId("box-club-side-events");
    await expect(events.getByText("Saturday partner WOD")).toBeVisible();
    await expect(page.getByText("Saturday partner WOD", { exact: true }).locator("visible=true")).toHaveCount(1);

    // A channel narrows the feed to it; again shows everything.
    const general = page.getByTestId("box-club-side-channels").getByRole("button", { name: "general" });
    await reachable(general);
    await general.click();
    await expect(general).toHaveAttribute("aria-pressed", "true");
    await expect.poll(() => feeds.some((url) => url.searchParams.get("channel_id") === "ch-gen")).toBe(true);
    await general.click();
    await expect(general).toHaveAttribute("aria-pressed", "false");

    // «All» channels opens the list in the main column, with a way back.
    const allChannels = page.getByTestId("box-club-side-channels").getByRole("button", { name: /All/ });
    await reachable(allChannels);
    await allChannels.click();
    const back = page.getByTestId("box-club-back");
    await reachable(back);
    await expect(club.getByText("From the box")).toBeVisible();
    await back.click();

    // «All» club members opens the list with its search.
    const allMembers = page.getByTestId("box-club-side-members").getByRole("button", { name: /All/ });
    await expect(page.getByTestId("box-club-side-members")).toContainText("3 members");
    await reachable(allMembers);
    await allMembers.click();
    await expect(page.getByPlaceholder("Search club members")).toBeVisible();
    await back.click();

    // «Write something to the club…» opens the compose sheet.
    const prompt = club.getByTestId("club-compose-prompt");
    await reachable(prompt);
    await prompt.click();
    await expect(page.getByRole("dialog", { name: "New post" })).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.getByRole("dialog", { name: "New post" })).toBeHidden();

    // «All» events goes to the page's one «Events» tab, which lists the club's events.
    const allEvents = events.getByRole("button", { name: /All/ });
    await reachable(allEvents);
    await allEvents.click();
    await expect(page).toHaveURL(/#events$/);
    await expect(page.getByRole("tablist", { name: "Page sections" }).getByRole("tab", { name: "Events" })).toHaveAttribute("aria-selected", "true");
    await expect(page.getByText("Saturday partner WOD", { exact: true }).locator("visible=true").first()).toBeVisible();
  });

  test("phones: a small Feed · Channels · Club members switch and «Message» under the name", async ({ page, isMobile }) => {
    test.skip(!isMobile, "phones keep the switch instead of the side column");
    await busyClub(page);
    await page.goto(`/b/${box.slug}`);

    const club = page.getByTestId("box-club-tab");
    const sections = club.getByRole("tablist", { name: "Club sections" });
    await expect(sections.getByRole("tab")).toHaveText(["Feed", "Channels", "Club members"]);
    await expect(page.getByTestId("box-club-side")).toHaveCount(0);
    // Members get no fixed action bar; «Message» sits under the name.
    await reachable(page.getByTestId("box-page-message").locator("visible=true").first());
    await expect(page.getByTestId("box-page-message").locator("visible=true").first()).toHaveText("Message");

    await reachable(club.getByTestId("club-compose-prompt"));
    // On phones the feed keeps its own events card.
    await expect(club.getByText("Saturday partner WOD", { exact: true })).toBeVisible();

    const membersTab = sections.getByRole("tab", { name: "Club members" });
    await reachable(membersTab);
    await membersTab.click();
    await expect(page.getByPlaceholder("Search club members")).toBeVisible();
    await sections.getByRole("tab", { name: "Channels" }).click();
    await expect(club.getByText("From the box")).toBeVisible();
    await sections.getByRole("tab", { name: "Feed" }).click();
    await expect(club.getByText("Who's in for Saturday's partner WOD?")).toBeVisible();
  });

  test("an empty club shows no filters over its feed", async ({ page }) => {
    await signedIn(page, { member: true });
    await page.route("**/api/me/feed**", (route) => route.fulfill(json({ posts: [], pinned: [], next_cursor: null })));
    await page.goto(`/b/${box.slug}`);
    const club = page.getByTestId("box-club-tab");
    await reachable(club.getByTestId("club-compose-prompt"));
    await expect(club.getByRole("button", { name: "Filters", exact: true })).toHaveCount(0);
  });

  test("desktop: the schedule shows the whole week, with its arrows, «Today» and the filters in one row", async ({ page, isMobile }) => {
    test.skip(isMobile, "phones keep the day strip");
    await signedIn(page);
    await page.goto(`/b/${box.slug}#schedule`);

    const grid = page.getByTestId("schedule-week-grid");
    await expect(grid.getByRole("listitem")).toHaveCount(7);
    await expect(grid.locator('[aria-current="date"]')).toHaveCount(1);
    // The filters are in the week's row, not behind a «Filters» button.
    await expect(page.getByRole("button", { name: "Filters", exact: true })).toHaveCount(0);
    await reachable(page.getByLabel("Level"));

    const range = page.getByTestId("schedule-week-range");
    const thisWeek = await range.textContent();
    const week = page.getByRole("navigation", { name: "Week" });
    const today = week.getByRole("button", { name: "Today" });
    await expect(today).toBeDisabled();
    const next = week.getByRole("button", { name: "Next week" });
    await reachable(next);
    await next.click();
    await expect(range).not.toHaveText(thisWeek ?? "");
    await expect(today).toBeEnabled();
    await today.click();
    await expect(range).toHaveText(thisWeek ?? "");

    // A class opens its sheet from the week.
    const yoga = grid.getByRole("button", { name: /Yoga 40\+/ });
    await reachable(yoga);
    await yoga.click();
    await expect(page.getByRole("dialog", { name: "Yoga 40+" })).toBeVisible();
  });
});
