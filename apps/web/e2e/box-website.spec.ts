import { createServer, type Server } from "node:http";

import { expect, test, type Page, type Route } from "./support/test";

import { stubApiPort } from "../playwright.config";

// W4 box website and reviews (ADR-386/387/388): Settings › Website and
// Settings › Reviews for staff, the public website on /b/<slug> and
// /b/<slug>/en with its request sheet, and the member's review ask and Box
// «Reviews». The API is stubbed; the public pages' server reads go to a stub
// API on `stubApiPort`.

const json = (route: Route, body: unknown, status = 200) =>
  route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
const tenantless = (path: string) => path.replace(/^\/api\/org\/[^/]+/, "/api");

type Write = { path: string; method: string; body: unknown };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// ── The public website ──────────────────────────────────────────────────────

const slug = "site-e2e-box";
const box = { organization_id: "org-1", slug, name: "Box Kypseli", logo_url: null, primary_color: "#D9743D" };
const publicBox = {
  box,
  followers_count: 3,
  profile: {
    about: "Ένα φιλικό box στην Κυψέλη.",
    disciplines: ["crossfit"],
    audiences: [],
    services: [],
    amenities: [],
    languages: ["el", "en"],
    cover: null,
    photos: [],
    coaches: [{ id: "coach-1", nickname: "Stelios", avatar_url: null, class_types: ["CrossFit"] }],
  },
  locations: [],
};

const memberReviews = [
  {
    id: "review-1",
    author_name: "Maria",
    body: "Great coaches and a warm community.",
    rating: 5,
    created_at: "2026-10-01T10:00:00Z",
    edited_at: null,
    reply: { body: "Thank you, Maria!", replied_at: "2026-10-02T10:00:00Z" },
  },
  { id: "review-2", author_name: null, body: "Good box.", rating: 4, created_at: "2026-09-20T10:00:00Z", edited_at: null, reply: null },
];

const google = {
  name: "Box Kypseli",
  rating: 4.7,
  count: 120,
  maps_uri: "https://maps.google.com/?cid=1",
  write_review_url: "https://search.google.com/local/writereview?placeid=place-1",
  fetched_at: "2026-11-01T10:00:00Z",
  reviews: [{ author_name: "Kostas", author_photo_uri: null, author_uri: null, published_at: null, rating: 5, relative_time: "a week ago", text: "Top box." }],
};

const site = {
  slug,
  language: "el",
  languages: ["el", "en"],
  canonical_url: `https://palee.app/b/${slug}`,
  time_zone: "Europe/Athens",
  about_en: "A friendly box in Kypseli.",
  sections: ["hero", "about", "faq", "reviews", "trial_form", "contact_form", "coaches"],
  faq: [{ question: "Χρειάζομαι εμπειρία;", answer: "Όχι, ξεκινάμε από την αρχή.", question_en: "Do I need experience?", answer_en: "No, we start from scratch." }],
  forms: { trial: true, contact: true, kinds: ["trial", "contact"] },
  reviews: { palee: { average: 4.5, count: 2, latest: memberReviews }, google, google_reviews_url: google.maps_uri },
  report_contact: "moderation@palee.app",
  events: [],
  timetable: [],
  wod: [],
  tracking: {
    banner_version: 1,
    categories: ["necessary"],
    consent_required: false,
    tags: { ga4_measurement_id: null, gtm_container_id: null, meta_pixel_id: null },
    validity_days: 180,
  },
};


let server: Server;

test.beforeAll(async () => {
  server = createServer((request, response) => {
    const url = request.url ?? "";
    const reply = (status: number, body: unknown) => {
      response.writeHead(status, { "content-type": "application/json" });
      response.end(JSON.stringify(body));
    };
    if (url.startsWith(`/api/public/boxes/${slug}`)) return reply(200, publicBox);
    if (url.startsWith(`/api/public/sites/${slug}`)) return reply(200, site);
    return reply(404, { error: "not_found" });
  });
  await new Promise<void>((resolve) => server.listen(stubApiPort, "127.0.0.1", resolve));
});

test.afterAll(async () => {
  await new Promise((resolve) => server.close(resolve));
});

async function asVisitor(page: Page, { appLocale = true } = {}) {
  const forms: Write[] = [];
  if (appLocale) await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const url = new URL(route.request().url());
    const method = route.request().method();
    if (method !== "GET" && url.pathname !== "/api/auth/refresh") forms.push({ path: url.pathname, method, body: route.request().postDataJSON() });
    if (url.pathname === "/api/auth/refresh") return json(route, { error: "unauthorized" }, 401);
    if (url.pathname.startsWith(`/api/public/sites/${slug}/forms/`)) return json(route, { status: "received" }, 202);
    return json(route, {});
  });
  return forms;
}

test.describe("the box's public website", () => {
  test("shows the owner's sections in order, without the box page's «I'm interested» card", async ({ page }) => {
    await asVisitor(page);
    await page.goto(`/b/${slug}`);

    const sections = page.getByTestId("site-sections");
    await expect(sections).toBeVisible();
    await expect(sections.getByText("Ένα φιλικό box στην Κυψέλη.")).toBeVisible();
    const order = await sections
      .locator("[data-testid='site-faq'], [data-testid='site-reviews'], [data-testid='site-trial-card'], [data-testid='site-contact-card']")
      .evaluateAll((nodes) => nodes.map((node) => node.getAttribute("data-testid")));
    expect(order).toEqual(["site-faq", "site-reviews", "site-trial-card", "site-contact-card"]);
    // «Coaches» comes last, after the forms, as the owner ordered it.
    const coachesAfterForms = await sections.evaluate((root) => {
      const contact = root.querySelector("[data-testid='site-contact-card']")!;
      const coach = [...root.querySelectorAll("*")].find((node) => node.textContent === "Stelios")!;
      return Boolean(contact.compareDocumentPosition(coach) & Node.DOCUMENT_POSITION_FOLLOWING);
    });
    expect(coachesAfterForms).toBe(true);

    // In-app reviews and Google's rating, kept apart (ADR-386/387).
    const reviews = sections.getByTestId("site-reviews");
    await expect(reviews.getByTestId("site-reviews-average")).toContainText("4.5");
    await expect(reviews.getByTestId("site-reviews-average")).toContainText("2 reviews");
    await expect(reviews.getByText("Great coaches and a warm community.")).toBeVisible();
    await expect(reviews.getByTestId("box-review-reply").first()).toContainText("Reply from Box Kypseli: Thank you, Maria!");
    await expect(reviews.getByTestId("google-reviews")).toContainText("From Google");
    await expect(reviews.getByTestId("google-reviews")).toContainText("120 Google reviews");

    // FAQ in the box's language on the box-language page.
    await expect(sections.getByTestId("site-faq").getByText("Χρειάζομαι εμπειρία;")).toBeVisible();

    // The website has its own request cards, so the W2 enquiry card is not shown (ADR-388).
    await expect(page.getByTestId("enquiry-open")).toHaveCount(0);
    await expect(page.getByText("I'm interested", { exact: true })).toHaveCount(0);

    await expect(page.getByTestId("site-language-switch").getByRole("link", { name: "el" })).toHaveAttribute("aria-current", "page");

    // The footer names Palee's moderation address for reports on content (ADR-397).
    await expect(page.getByTestId("site-report-contact")).toHaveAttribute("href", "mailto:moderation@palee.app");
    await expect(page.getByTestId("site-report-contact")).toContainText("moderation@palee.app");
  });

  test("the trial request sheet sends the form with an event_id and the privacy yes", async ({ page }) => {
    const forms = await asVisitor(page);
    await page.goto(`/b/${slug}`);

    await page.getByTestId("site-trial-card").getByRole("button", { name: "Book a trial class" }).click();
    const sheet = page.getByRole("dialog", { name: "Book a trial class" });
    await expect(sheet).toContainText("Nothing is booked yet.");
    await sheet.getByLabel("Name").fill("Nikos Ioannou");
    await sheet.getByLabel("Mobile or email").fill("6900000001");
    await sheet.getByLabel("When suits you (optional)").fill("weekday evenings");

    // The privacy yes is required before anything is sent.
    await sheet.getByRole("button", { name: "Send request" }).click();
    await expect(sheet.getByText("Confirm you have read the privacy policy.")).toBeVisible();
    expect(forms).toEqual([]);

    await sheet.getByRole("checkbox", { name: /privacy policy/ }).check();
    await sheet.getByRole("button", { name: "Send request" }).click();

    await expect(page.getByRole("dialog", { name: "Request sent" })).toBeVisible();
    expect(forms).toHaveLength(1);
    expect(forms[0]!.path).toBe(`/api/public/sites/${slug}/forms/trial`);
    const body = forms[0]!.body as Record<string, unknown>;
    expect(body).toMatchObject({
      name: "Nikos Ioannou",
      phone: "6900000001",
      preferred_time: "weekday evenings",
      locale: "en",
      marketing_opt_in: false,
      privacy_ack: true,
      website: "",
      attribution: { landing_path: `/b/${slug}` },
    });
    expect(body.event_id).toEqual(expect.stringMatching(UUID));
    expect(body.elapsed_ms).toEqual(expect.any(Number));
    expect(body).not.toHaveProperty("email");
    expect(body).not.toHaveProperty("visitor_id");
  });

  test("/en shows the owner's English texts and marks English as current", async ({ page }) => {
    await asVisitor(page);
    await page.goto(`/b/${slug}/en`);

    const sections = page.getByTestId("site-sections");
    await expect(sections.getByText("A friendly box in Kypseli.")).toBeVisible();
    await expect(sections.getByText("Ένα φιλικό box στην Κυψέλη.")).toHaveCount(0);
    await expect(sections.getByTestId("site-faq").getByText("Do I need experience?")).toBeVisible();
    await expect(page.getByTestId("site-language-switch").getByRole("link", { name: "en" })).toHaveAttribute("aria-current", "page");
    await expect(page.getByTestId("enquiry-open")).toHaveCount(0);
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute("href", new RegExp(`/b/${slug}/en$`));
  });

  test("a first visit from an English browser opens /en", async ({ page }) => {
    await asVisitor(page, { appLocale: false });
    await page.goto(`/b/${slug}`);
    await expect(page).toHaveURL(new RegExp(`/b/${slug}/en$`));
    await expect(page.getByTestId("site-sections").getByText("A friendly box in Kypseli.")).toBeVisible();
  });
});

// ── Staff: Settings › Website and Settings › Reviews ─────────────────────────

const owner = {
  id: "owner-1",
  nickname: "Apostolos",
  role: "admin",
  email: "owner-1@example.com",
  email_verified: true,
  completed_tours: ["admin", "member", "athlete", "first_run"],
  preferred_locale: "en",
  vendor: false,
  memberships: [{ organization_slug: "kypseli", role: "owner", settings: {} }],
};

function tokenFor(user: { id: string; role: string }) {
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: user.role, memberships: [{ organization_slug: "kypseli" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  return `stub.${payload}.signature`;
}

const ownerMembership = {
  role: "owner",
  roles: ["owner"],
  capabilities: { manage_settings: true, message_from_box: true, view_analytics: true },
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", activation: "active", timezone: "Europe/Athens", timezone_confirmed: true },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

async function asOwner(page: Page, writes: Write[], extra: (path: string, method: string, body: unknown, route: Route) => Promise<void> | null) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    const body = method === "GET" ? null : route.request().postDataJSON();
    if (method !== "GET") writes.push({ path, method, body });
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(owner), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, owner);
    if (path === "/api/memberships") return json(route, [ownerMembership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/public/status") return json(route, { status: "operational", generated_at: new Date().toISOString(), components: [], active: [], upcoming: [] });
    const handled = extra(path, method, body, route);
    if (handled) return handled;
    return json(route, {});
  });
}

const siteSettings = {
  about_en: null,
  banner_version: 1,
  conversions_api_enabled: false,
  faq: [],
  forms_enabled: true,
  ga4_measurement_id: null,
  gtm_container_id: null,
  has_conversions_api_token: false,
  hidden_sections: [],
  lock_version: 3,
  meta_pixel_id: null,
  public_schedule: false,
  public_wod: false,
  section_order: ["hero", "about", "schedule", "reviews", "trial_form", "contact_form", "faq"],
};

test.describe("Settings › Website", () => {
  test("switches sections and their order as a draft, and the save bar sends one PUT", async ({ page }) => {
    const writes: Write[] = [];
    await asOwner(page, writes, (path, method, body, route) => {
      if (path === "/api/admin/site" && method === "GET") return json(route, { settings: siteSettings, domains: [] });
      if (path === "/api/admin/site" && method === "PUT") return json(route, { settings: { ...siteSettings, ...(body as object), lock_version: 4 } });
      if (path === "/api/admin/site/summary") {
        return json(route, { days: 30, submissions: { total: 7, delivered: 7, failed: 0, waiting: 0 }, consents: { accept_all: 0, custom: 0, reject_all: 0, withdraw: 0 } });
      }
      return null;
    });
    await page.goto("/admin/settings/website");

    await expect(page.getByRole("heading", { name: "Website", level: 1 })).toBeVisible();
    await expect(page.getByTestId("website-summary")).toHaveText("7 requests in the last 30 days");
    await expect(page.getByTestId("website-open")).toHaveAttribute("href", "/b/kypseli");

    const sections = page.getByTestId("website-sections");
    await expect(sections.getByTestId("website-section-hero")).toContainText("Always shown first");
    // «Timetable» is off until the owner switches it on (public_schedule).
    const timetable = sections.getByRole("switch", { name: "Timetable" });
    await expect(timetable).not.toBeChecked();
    await expect(sections.getByRole("switch", { name: "Contact form" })).toBeChecked();
    await expect(page.getByTestId("website-save-bar-save")).toHaveCount(0);

    await timetable.check();
    await sections.getByRole("switch", { name: "Contact form" }).uncheck();
    await sections.getByRole("button", { name: "Move Reviews up" }).click();
    await expect(sections.locator("li")).toHaveText([/^Top/, /^About/, /^Reviews/, /^Timetable/, /^Trial class request/, /^Contact form/, /^FAQ/]);
    await expect(page.getByTestId("website-save-bar-count")).toHaveText("3 unsaved changes");
    expect(writes.filter((write) => write.path === "/api/admin/site")).toEqual([]);

    await page.getByTestId("website-save-bar-save").click();
    await expect(page.getByTestId("website-save-bar")).toContainText("Changes saved.");
    const puts = writes.filter((write) => write.path === "/api/admin/site" && write.method === "PUT");
    expect(puts).toHaveLength(1);
    expect(puts[0]!.body).toMatchObject({
      lock_version: 3,
      public_schedule: true,
      public_wod: false,
      forms_enabled: true,
      hidden_sections: ["contact_form"],
      section_order: ["hero", "about", "reviews", "schedule", "trial_form", "contact_form", "faq"],
      faq: [],
      about_en: null,
    });
  });

  // ADR-398: Palee creates the Ingress of a verified host; the card shows the certificate's state.
  test("the domain card says how the automatic certificate is doing", async ({ page }) => {
    const writes: Write[] = [];
    const domain = (host: string, extra: object) => ({
      id: `domain-${host}`,
      host,
      primary: host.startsWith("www."),
      status: "pending_tls",
      last_error: "tls_not_ready",
      checked_at: new Date().toISOString(),
      next_check_at: new Date().toISOString(),
      verified_at: new Date().toISOString(),
      active_at: null,
      certificate_status: "issuing",
      certificate_error: null,
      dns_records: [{ type: "CNAME", name: host, value: "sites.palee.app" }],
      ...extra,
    });
    await asOwner(page, writes, (path, method, _body, route) => {
      if (path === "/api/admin/site" && method === "GET") {
        return json(route, {
          settings: siteSettings,
          domains: [domain("www.kypseli.gr", {}), domain("kypseli.gr", { certificate_status: "failed", certificate_error: "challenge_failed" })],
        });
      }
      if (path === "/api/admin/site/summary") {
        return json(route, { days: 30, submissions: { total: 0, delivered: 0, failed: 0, waiting: 0 }, consents: { accept_all: 0, custom: 0, reject_all: 0, withdraw: 0 } });
      }
      return null;
    });
    await page.goto("/admin/settings/website");

    const cards = page.getByTestId("website-domain");
    await expect(cards).toHaveCount(2);
    await expect(cards.nth(0).getByTestId("site-domain-certificate")).toHaveText("The certificate is being issued. This usually takes a few minutes.");
    await expect(cards.nth(1).getByTestId("site-domain-certificate")).toContainText("Let's Encrypt couldn't reach the domain");
    // Only the background session refresh and the time-zone sync write; the domain card writes nothing.
    expect(writes.filter((write) => write.path.startsWith("/api/admin/site"))).toEqual([]);
  });
});

test.describe("Settings › Reviews", () => {
  async function reviewsSettings(page: Page) {
    const writes: Write[] = [];
    const askSettings = (enabled: boolean, lock: number) => ({
      google,
      settings: { enabled, google_place_id: "place-1", google_review_url: google.write_review_url, lock_version: lock, milestones: [10, 50, 100] },
    });
    await asOwner(page, writes, (path, method, _body, route) => {
      if (path === "/api/admin/review-asks/settings" && method === "GET") return json(route, askSettings(false, 2));
      if (path === "/api/admin/review-asks/settings" && method === "PUT") return json(route, askSettings(true, 3));
      if (path === "/api/admin/review-asks/summary") {
        return json(route, { days: 30, counts: { asked: 12, opened: 5, dismissed: 2, later: 1, opted_out: 0, unanswered: 4 } });
      }
      if (path === "/api/admin/box-reviews") return json(route, { average: 4.5, count: 2, has_more: false, google: null, reviews: memberReviews });
      if (path === "/api/admin/box-reviews/review-2/reply") {
        return json(route, { review: { ...memberReviews[1], reply: { body: "Thanks!", replied_at: new Date().toISOString() } } });
      }
      return null;
    });
    await page.goto("/admin/settings/reviews");
    return writes;
  }

  test("shows the Google listing apart, switches the ask on, and lists the members' reviews", async ({ page }) => {
    const writes = await reviewsSettings(page);

    await expect(page.getByRole("heading", { name: "Reviews", level: 1 })).toBeVisible();
    const listing = page.getByTestId("reviews-google");
    await expect(listing.getByTestId("google-reviews")).toContainText("120 Google reviews");
    // ADR-390: Google shows only the rating and the count; review texts never show, even if sent.
    await expect(listing.getByText("Top box.")).toHaveCount(0);

    await expect(page.getByTestId("reviews-ask-summary")).toHaveText("Last 30 days: asked 12, answered 5");
    const ask = page.getByTestId("reviews-ask-switch");
    await expect(ask).not.toBeChecked();
    await ask.click();
    await expect
      .poll(() => writes.find((write) => write.path === "/api/admin/review-asks/settings"))
      .toEqual({ path: "/api/admin/review-asks/settings", method: "PUT", body: { enabled: true, lock_version: 2 } });
    await expect(ask).toBeChecked();

    const members = page.getByTestId("reviews-members");
    await expect(members).toContainText("Reviews cannot be deleted; you can reply publicly.");
    await expect(members.getByTestId("box-review")).toHaveCount(2);
    // Maria's review already has a reply; the anonymous one does not.
    await expect(members.getByTestId("reviews-reply")).toHaveText(["Edit reply", "Reply"]);
  });

  test("a reply to a member's review is published with one PUT", async ({ page }) => {
    const writes = await reviewsSettings(page);
    const members = page.getByTestId("reviews-members");
    await members.getByTestId("reviews-reply").nth(1).click();
    const dialog = page.getByRole("dialog", { name: "Your reply" });
    await dialog.getByRole("textbox", { name: "Your reply" }).fill("Thanks!");
    await dialog.getByRole("button", { name: "Publish reply" }).click();
    await expect(dialog).toBeHidden();
    await expect(page).toHaveURL(/\/admin\/settings\/reviews$/);
    expect(writes.find((write) => write.path === "/api/admin/box-reviews/review-2/reply")).toEqual({
      path: "/api/admin/box-reviews/review-2/reply",
      method: "PUT",
      body: { body: "Thanks!" },
    });
  });
});

// ── Members: the review ask on Home and «Reviews» in Box ────────────────────

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

const memberMembership = {
  role: "member",
  roles: ["member"],
  capabilities: {},
  organization: { id: "org-1", slug: "kypseli", name: "Box Kypseli", activation: "active", timezone: "Europe/Athens", timezone_confirmed: true },
  settings: { brand_name: "Box Kypseli", brand_logo_url: null, brand_primary_color: null },
};

async function asMember(page: Page, writes: Write[], extra: (path: string, method: string, route: Route) => Promise<void> | null) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", async (route) => {
    const path = tenantless(new URL(route.request().url()).pathname);
    const method = route.request().method();
    if (method !== "GET") writes.push({ path, method, body: route.request().postDataJSON() });
    if (path === "/api/auth/refresh") return json(route, { access_token: tokenFor(member), refresh_token: "refresh" });
    if (path === "/api/auth/me") return json(route, member);
    if (path === "/api/memberships") return json(route, [memberMembership]);
    if (path.startsWith("/api/notifications")) return json(route, { notifications: [], unread_count: 0 });
    if (path === "/api/public/status") return json(route, { status: "operational", generated_at: new Date().toISOString(), components: [], active: [], upcoming: [] });
    if (path === "/api/me/feed") return json(route, { posts: [], pinned: [], next_cursor: null });
    if (path === "/api/me/channels") return json(route, { channels: [], contact: null, consents: [] });
    if (path === "/api/me/clubs") {
      return json(route, {
        clubs: [{ id: "club-1", kind: "gym", name: "Box Kypseli", organization_id: "org-1", organization_slug: "kypseli", role: "member", notify_level: "all", logo_url: null, primary_color: null, channels: [] }],
      });
    }
    const handled = extra(path, method, route);
    if (handled) return handled;
    // Quiet defaults for the other Home and Box cards.
    if (path === "/api/me/box-reviews") return json(route, { average: null, count: 0, can_review: false, has_more: false, google: null, mine: null, reviews: [] });
    if (path === "/api/executions") return json(route, { executions: [] });
    if (path === "/api/me/trials") return json(route, { trials: [] });
    if (path === "/api/community/wod-today") return json(route, { date: null, channel_id: null, classes: [], leaderboard: [], logged_by_me: false, score: null, workout: null });
    return json(route, {});
  });
}

test.describe("members' reviews", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  async function homeWithAsk(page: Page) {
    const writes: Write[] = [];
    await asMember(page, writes, (path, method, route) => {
      if (path === "/api/me/review-ask") {
        return json(route, {
          ask: { id: "ask-1", milestone: 10, status: "shown", shown_at: new Date().toISOString(), has_review: false, google_review_url: google.write_review_url, actions: ["opened", "later", "dismissed"] },
        });
      }
      if (path === "/api/me/review-asks/ask-1/respond") return json(route, { ask: null });
      if (path === "/api/me/box-review" && method === "PUT") return json(route, { review: { ...memberReviews[0], id: "mine-1" } });
      return null;
    });
    // A member of one box opens the app on Box (W7 screen 12); the ask sits on Feed.
    await page.goto("/");
    // The dev server may compile /box on its first visit, which can take longer than the default wait.
    await expect(page).toHaveURL(/\/box$/, { timeout: 30_000 });
    // The dev build's Next.js indicator sits over the bottom bar's first item, so the tap is dispatched.
    await page.getByRole("navigation", { name: "Main sections" }).getByRole("link", { name: "Feed" }).dispatchEvent("click");
    await expect(page).toHaveURL(/\/$/);
    return writes;
  }

  test("after the 10th class Home asks once; «Write a review» opens the sheet and records the answer", async ({ page }) => {
    const writes = await homeWithAsk(page);
    const card = page.getByTestId("review-ask-card");
    await expect(card).toContainText("10 classes done!");
    await expect(card).toContainText("How is it going at Box Kypseli?");
    await expect(card.getByTestId("review-ask-google")).toHaveAttribute("href", google.write_review_url);
    await expect(card.getByTestId("review-ask-message")).toBeVisible();

    await card.getByTestId("review-ask-write").click();
    const sheet = page.getByRole("dialog", { name: "Review Box Kypseli" });
    await expect(sheet.getByRole("radiogroup", { name: "Your rating" })).toBeVisible();
    await expect(page.getByTestId("review-ask-card")).toHaveCount(0);
    await expect.poll(() => writes.find((write) => write.path === "/api/me/review-asks/ask-1/respond")?.body).toEqual({ action: "opened" });
  });

  test("the review sheet asks for stars, then publishes the stars and words", async ({ page }) => {
    const writes = await homeWithAsk(page);
    await page.getByTestId("review-ask-card").getByTestId("review-ask-write").click();
    const sheet = page.getByRole("dialog", { name: "Review Box Kypseli" });
    await sheet.getByRole("button", { name: "Publish" }).click();
    await expect(sheet.getByText("Choose from 1 to 5 stars.")).toBeVisible();
    await sheet.getByRole("radio", { name: "5 out of 5 stars" }).click();
    await sheet.getByLabel("A few words (optional)").fill("Love it here.");
    await sheet.getByRole("button", { name: "Publish" }).click();
    await expect(sheet).toBeHidden();
    expect(writes.find((write) => write.path === "/api/me/box-review")).toEqual({
      path: "/api/me/box-review",
      method: "PUT",
      body: { rating: 5, body: "Love it here.", locale: "en" },
    });
  });

  test("Box shows «Reviews» with my review and Google's rating apart", async ({ page }) => {
    await asMember(page, [], (path, _method, route) => {
      if (path === "/api/me/box-reviews") {
        return json(route, { average: 4.5, count: 2, can_review: true, has_more: false, google, mine: memberReviews[0], reviews: memberReviews });
      }
      return null;
    });
    await page.goto("/box");

    const section = page.getByTestId("box-reviews");
    await expect(section.getByRole("heading", { name: "Reviews" })).toBeVisible();
    await expect(section.getByTestId("box-reviews-average")).toContainText("2 reviews");
    await expect(section.getByTestId("box-reviews-mine")).toContainText("Great coaches and a warm community.");
    // One review per member: no «Write a review» once mine exists.
    await expect(section.getByTestId("box-reviews-write")).toHaveCount(0);
    await expect(section.getByTestId("box-review")).toHaveCount(2);
    await expect(section.getByTestId("google-reviews")).toContainText("From Google");
  });
});
