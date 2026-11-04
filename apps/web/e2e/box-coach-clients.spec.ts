import { chooseOption } from "./support/select";
import { expect, test, type Page, type Request } from "./support/test";

// ADR-198 (vision §7.10): a coach finds their coaching work in Box ›
// «Πελάτες μου»: the reply queue, form reviews, today's check-in desk (with
// one skill for the class, ADR-400), who meets their rank's requirements and
// their clients, each part hidden when empty. The API is stubbed; every
// route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");

const coachCapabilities = { manage_coaching: "own", run_classes: "own", manage_appointments: "own", check_in: "own" };

function persona(roles: string[]) {
  const user = {
    id: "coach-1",
    nickname: "Nikos",
    role: "member",
    email: "coach@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: false,
    memberships: [{ organization_slug: "box1", role: roles[0], settings: {} }],
  };
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, role: "member", memberships: [{ organization_slug: "box1" }], exp: Math.floor(Date.now() / 1000) + 3600 }),
  ).toString("base64url");
  const membership = {
    role: roles[0],
    roles,
    capabilities: roles.includes("coach") ? coachCapabilities : {},
    organization: { id: "org-1", slug: "box1", name: "Box One", provider_kind: "gym", timezone: "UTC" },
    settings: { brand_name: "Box One", brand_logo_url: null, brand_primary_color: null },
  };
  return { user, token: `stub.${payload}.signature`, membership };
}

async function common(page: Page, roles: string[]) {
  const { user, token, membership } = persona(roles);
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.addInitScript(() => {
    window.localStorage.setItem("palee:selected-organization-slug", "box1");
    // Staff open the social app from the console's «Social» switch (ADR-103).
    window.localStorage.setItem("palee.view", "client");
  });
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: token, refresh_token: "refresh" })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([membership])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
  await page.route("**/api/me/clubs", (route) => route.fulfill(json({ clubs: [] })));
  await page.route(/\/api\/(org\/[^/]+\/)?executions(\?|$)/, (route) => route.fulfill(json({ executions: [] })));
}

function classSlot(attended: boolean) {
  return {
    id: "slot-1",
    master_workout_id: null,
    name: "WOD 18:00",
    duration_minutes: 60,
    // Now: today in any zone.
    scheduled_at: new Date().toISOString(),
    class_type_id: "ct",
    class_type: { id: "ct", name: "CrossFit" },
    capacity: 12,
    auto_approve: true,
    booking_timeout_minutes: 30,
    approved_booking_count: 2,
    spots_remaining: 10,
    workout: null,
    coach_user_id: "coach-1",
    bookings: [
      { id: "bk-1", user_id: "u-1", user_nickname: "Eleni", status: "approved", inserted_at: "2026-10-01T00:00:00Z", attendance_status: "attended" },
      { id: "bk-2", user_id: "u-2", user_nickname: "Kostas", status: "approved", inserted_at: "2026-10-01T00:00:00Z", attendance_status: attended ? "attended" : null },
    ],
  };
}

test.describe("Box › My clients", () => {
  test("a coach answers, reviews, checks in and finds their clients", async ({ page }) => {
    await common(page, ["coach"]);
    await page.setViewportSize({ width: 360, height: 800 });
    let kostasIn = false;
    let attendance: Record<string, unknown> | null = null;
    let feedback: Record<string, unknown> | null = null;

    await page.route("**/api/org/box1/staff/reply-queue", (route) =>
      route.fulfill(
        json({
          replies: [
            { message_id: "m-1", thread_id: "t-1", client_id: "u-1", client_nickname: "Eleni", sent_at: new Date(Date.now() - 3 * 3600_000).toISOString(), overdue: true },
          ],
        }),
      ),
    );
    await page.route("**/api/org/box1/staff/form-reviews?**", (route) =>
      route.fulfill(
        json({
          form_reviews: feedback
            ? []
            : [
                {
                  id: "fr-1",
                  user_id: "u-2",
                  nickname: "Kostas",
                  exercise_name: "Snatch",
                  note: "Is my catch too low?",
                  status: "submitted",
                  video_url: "https://video.example.com/snatch",
                  inserted_at: new Date(Date.now() - 3600_000).toISOString(),
                },
              ],
        }),
      ),
    );
    await page.route("**/api/org/box1/staff/form-reviews/fr-1/review", (route) => {
      feedback = bodyOf(route.request());
      return route.fulfill(json({ form_review: { id: "fr-1", status: "reviewed" } }));
    });
    await page.route("**/api/org/box1/staff/coaching-relationships?**", (route) =>
      route.fulfill(
        json({
          relationships: [
            { id: "r-1", client_user_id: "u-1", client_nickname: "Eleni", coach_user_id: "coach-1", origin: "assigned" },
            { id: "r-2", client_user_id: "u-2", client_nickname: "Kostas", coach_user_id: "coach-1", origin: "self_assigned" },
          ],
        }),
      ),
    );
    await page.route("**/api/org/box1/schedule?**", (route) => route.fulfill(json({ class_types: [], locations: [], coaches: [], slots: [classSlot(kostasIn)] })));
    await page.route("**/api/org/box1/staff/appointment-slots?**", (route) => route.fulfill(json({ slots: [] })));
    await page.route("**/api/org/box1/admin/schedule/slots/slot-1/attendance/u-2", (route) => {
      attendance = bodyOf(route.request());
      kostasIn = true;
      return route.fulfill(json({ attendance: { status: "attended" } }));
    });

    await page.goto("/box");
    const section = page.getByTestId("box-coach-clients");
    await expect(section.getByRole("heading", { name: "My clients" })).toBeVisible();

    // The reply queue opens the thread itself.
    await expect(section.getByRole("link", { name: /Eleni.*Overdue/ })).toHaveAttribute("href", "/messages?filter=coach&thread=t-1");

    // Today's desk: 1 of 2 in; Kostas is marked from the roster.
    const deskRow = section.getByRole("button", { name: /WOD 18:00/ });
    await expect(deskRow).toContainText("1 of 2 checked in");
    await deskRow.click();
    const roster = page.getByRole("dialog");
    await roster.getByRole("group", { name: "Attendance of Kostas" }).getByRole("button", { name: "Here" }).click();
    await expect.poll(() => attendance).toEqual({ status: "attended" });
    await expect(roster.getByRole("group", { name: "Attendance of Kostas" }).getByRole("button", { name: "✓ Here" })).toHaveAttribute("aria-pressed", "true");
    await roster.getByRole("button", { name: "Close" }).click();
    await expect(deskRow).toContainText("2 of 2 checked in");

    // Clients link to their console profile.
    await expect(section.getByRole("link", { name: /Kostas/ })).toHaveAttribute("href", "/org/box1/admin/users/u-2");

    // No horizontal scroll at 360px.
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);

    // A form review is answered in a sheet with the console's own form.
    await section.getByRole("button", { name: /Kostas.*Snatch/ }).click();
    const sheet = page.getByRole("dialog");
    await expect(sheet.getByRole("link", { name: "Watch the video" })).toHaveAttribute("href", "https://video.example.com/snatch");
    await expect(sheet.getByText("Is my catch too low?")).toBeVisible();
    await sheet.getByRole("textbox").fill("Catch is fine, drive the hips.");
    await sheet.getByRole("button", { name: "Send feedback" }).click();
    await expect.poll(() => feedback).toEqual({ feedback: "Catch is fine, drive the hips." });
    // With nothing left to review, that part is gone.
    await expect(section.getByRole("button", { name: /Kostas.*Snatch/ })).toHaveCount(0);
  });

  test("a coach ticks one skill for the class and opens a ready person's promotion (ADR-400)", async ({ page }) => {
    await common(page, ["coach"]);
    let batch: Record<string, unknown> | null = null;
    const blue = { id: "r-blue", position: 1, name: "Blue", color: "blue", max_stripes: 4, requirements: { skills: ["Armbar", "Triangle"], skill_ids: ["s-1", "s-2"] } };
    const ladder = { id: "ladder-1", name: "BJJ", discipline: "bjj_grappling", style: "belt", class_type_ids: [], ready_criteria: ["classes", "days"], ranks: [blue] };
    await page.route("**/api/org/box1/schedule?**", (route) => route.fulfill(json({ class_types: [], locations: [], coaches: [], slots: [classSlot(true)] })));
    await page.route("**/api/org/box1/staff/appointment-slots?**", (route) => route.fulfill(json({ slots: [] })));
    await page.route("**/api/org/box1/staff/ranks/skills/batch**", (route) => {
      if (route.request().method() === "PUT") {
        batch = bodyOf(route.request());
        return route.fulfill(json({ changed: ["u-1"], skipped: [] }));
      }
      return route.fulfill(
        json({
          ladders: [ladder],
          people: [
            { user_id: "u-1", reachable: true, next_rank_ids: ["r-blue"], checked: [] },
            { user_id: "u-2", reachable: false, next_rank_ids: ["r-blue"], checked: [] },
          ],
        }),
      );
    });
    await page.route("**/api/org/box1/staff/ranks/ready", (route) =>
      route.fulfill(json({ people: [{ user_id: "u-1", nickname: "Eleni", ladder: { id: "ladder-1", name: "BJJ", style: "belt" }, next: { id: "r-blue", name: "Blue", color: "blue" } }] })),
    );
    await page.route("**/api/org/box1/staff/clients/u-1/ranks", (route) =>
      route.fulfill(
        json({
          ladders: [
            {
              ladder,
              current: null,
              next: blue,
              progress: { rank_id: "r-blue", classes: { done: 80, needed: 80 }, days: { done: 760, needed: 730 }, skills: ["Armbar", "Triangle"], skills_checked: [], ready: true },
              history: [],
            },
          ],
        }),
      ),
    );

    await page.goto("/box");
    const section = page.getByTestId("box-coach-clients");

    // «Meets the requirements»: a row opens the promotion sheet; the coach decides.
    const ready = section.getByTestId("rank-ready-list");
    await expect(ready).toContainText("Eleni");
    await ready.getByRole("button", { name: /Eleni/ }).click();
    await expect(page.getByTestId("promote-sheet")).toBeVisible();
    await page.getByTestId("promote-sheet").getByRole("button", { name: "Cancel" }).click();

    // Mockup 3B: in the class, one skill for several people; Kostas is not this coach's client.
    await section.getByRole("button", { name: /WOD 18:00/ }).click();
    await page.getByTestId("class-skill-open").click();
    const sheet = page.getByTestId("class-skill-sheet");
    await chooseOption(page, sheet.getByRole("combobox"), "r-blue:s-1");
    await expect(sheet.getByRole("button", { name: /Kostas/ })).toBeDisabled();
    await sheet.getByRole("button", { name: /Eleni/ }).click();
    await sheet.getByRole("button", { name: "Save" }).click();
    await expect.poll(() => batch).toEqual({ rank_id: "r-blue", skill_id: "s-1", user_ids: ["u-1"] });
  });

  test("someone who does not coach here never sees the section", async ({ page }) => {
    await common(page, ["member"]);
    await page.goto("/box");
    await expect(page.getByRole("heading", { name: "Box One" })).toBeVisible();
    await expect(page.getByTestId("box-coach-clients")).toHaveCount(0);
  });

  test("a coach with nothing to do sees no empty section", async ({ page }) => {
    await common(page, ["coach"]);
    await page.route("**/api/org/box1/staff/reply-queue", (route) => route.fulfill(json({ replies: [] })));
    await page.route("**/api/org/box1/staff/form-reviews?**", (route) => route.fulfill(json({ form_reviews: [] })));
    await page.route("**/api/org/box1/staff/coaching-relationships?**", (route) => route.fulfill(json({ relationships: [] })));
    await page.route("**/api/org/box1/schedule?**", (route) => route.fulfill(json({ class_types: [], locations: [], coaches: [], slots: [] })));
    await page.route("**/api/org/box1/staff/appointment-slots?**", (route) => route.fulfill(json({ slots: [] })));
    await page.goto("/box");
    await expect(page.getByRole("heading", { name: "Box One" })).toBeVisible();
    await expect(page.getByTestId("box-coach-clients")).toHaveCount(0);
  });
});
