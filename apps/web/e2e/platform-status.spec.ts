import { expect, test, type Page, type Request } from "./support/test";

// ADR-366, W7 screen 2: /platform/status «Service status». «Now» shows the
// automatic checks; «New problem or maintenance» opens the form; the text is
// written in any language and Palee shows an English translation, marked
// «automatic translation», that the publisher may correct. When the
// translation fails, the problem is published untranslated. Who published it
// is shown. The API is stubbed; every route not listed answers an empty object.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const bodyOf = (request: Request) => JSON.parse(request.postData() ?? "{}");
const KEYS = ["app", "search", "files", "email", "payments", "fiscal"];

async function signedInVendor(page: Page) {
  const user = {
    id: "vendor-1",
    nickname: "Nikos",
    role: "admin",
    email: "vendor-1@example.com",
    email_verified: true,
    completed_tours: ["admin", "member", "athlete", "first_run"],
    preferred_locale: "en",
    vendor: true,
    memberships: [],
  };
  const payload = Buffer.from(JSON.stringify({ sub: user.id, role: "admin", memberships: [], exp: Math.floor(Date.now() / 1000) + 3600 })).toString(
    "base64url",
  );
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ access_token: `stub.${payload}.signature`, refresh_token: "refresh", user })));
  await page.route("**/api/auth/me", (route) => route.fulfill(json(user)));
  await page.route("**/api/memberships", (route) => route.fulfill(json([])));
  await page.route("**/api/notifications?**", (route) => route.fulfill(json({ notifications: [] })));
}

const consoleBody = (incidents: unknown[] = []) => ({
  probes: KEYS.map((key) => ({
    key,
    status: key === "email" ? "degraded" : "operational",
    reason: key === "email" ? "daily limit" : null,
    checked_at: "2026-11-02T19:30:00Z",
    changed_at: "2026-11-02T19:12:00Z",
  })),
  incidents,
  subscribers: { confirmed: 37, waiting: 2 },
});

test.describe("Platform › Service status", () => {
  test("publishes a problem written in Greek with a corrected English translation", async ({ page }) => {
    await signedInVendor(page);
    await page.route("**/api/platform/status", (route) => route.fulfill(json(consoleBody())));
    await page.route("**/api/platform/status/translations", (route) =>
      route.fulfill(json({ locale: "el", title: "Email delays", body: "Receipts are late." })),
    );
    const published: Array<Record<string, unknown>> = [];
    await page.route("**/api/platform/status/incidents", (route) => {
      published.push(bodyOf(route.request()));
      return route.fulfill(json({ id: "i1" }, 201));
    });

    await page.goto("/platform/status");
    await expect(page.getByTestId("status-console-now")).toContainText("No problem has been written.");
    await expect(page.getByTestId("status-console-history")).not.toHaveAttribute("open", "");

    await page.getByRole("button", { name: "New problem or maintenance" }).click();
    await page.getByRole("button", { name: "Email", exact: true }).click();
    await page.getByLabel("Title").fill("Καθυστερήσεις στα email");
    await page.getByLabel("What is happening").fill("Τα αποδεικτικά αργούν.");
    await page.getByLabel("What is happening").blur();

    const preview = page.getByTestId("status-english-preview");
    await expect(preview).toContainText("automatic translation");
    await expect(preview).toContainText("Receipts are late.");
    await preview.getByRole("button", { name: "Correct" }).click();
    await page.getByLabel("English text").fill("Receipts are delayed by up to an hour.");

    await expect(page.getByRole("button", { name: "Cancel" })).toBeVisible();
    await page.getByRole("button", { name: "Publish", exact: true }).click();
    await expect.poll(() => published.length).toBe(1);
    expect(published[0]).toMatchObject({
      kind: "incident",
      components: ["email"],
      locale: "el",
      title_en: "Email delays",
      body_en: "Receipts are delayed by up to an hour.",
      en_source: "edited",
    });
  });

  test("publishes untranslated when the translation fails", async ({ page }) => {
    await signedInVendor(page);
    await page.route("**/api/platform/status", (route) => route.fulfill(json(consoleBody())));
    await page.route("**/api/platform/status/translations", (route) =>
      route.fulfill(json({ error: { code: "status_translation_unavailable" } }, 503)),
    );
    const published: Array<Record<string, unknown>> = [];
    await page.route("**/api/platform/status/incidents", (route) => {
      published.push(bodyOf(route.request()));
      return route.fulfill(json({ id: "i1" }, 201));
    });

    await page.goto("/platform/status");
    await page.getByRole("button", { name: "New problem or maintenance" }).click();
    await page.getByRole("button", { name: "Email", exact: true }).click();
    await page.getByLabel("Title").fill("Καθυστερήσεις στα email");
    await page.getByLabel("What is happening").fill("Τα αποδεικτικά αργούν.");
    await page.getByLabel("What is happening").blur();
    await expect(page.getByTestId("status-translation-failed")).toContainText("It will be published only in the language it was written in.");

    await page.getByRole("button", { name: "Publish", exact: true }).click();
    await expect.poll(() => published.length).toBe(1);
    expect(published[0]).not.toHaveProperty("title_en");
  });

  test("an open problem shows who published it", async ({ page }) => {
    await signedInVendor(page);
    await page.route("**/api/platform/status", (route) =>
      route.fulfill(
        json(
          consoleBody([
            {
              id: "i1",
              kind: "incident",
              title: "Καθυστερήσεις στα email",
              title_en: "Email delays",
              locale: "el",
              en_source: "auto",
              impact: "minor",
              status: "investigating",
              components: ["email"],
              scheduled_for: null,
              scheduled_until: null,
              started_at: "2026-11-02T19:12:00Z",
              resolved_at: null,
              published_by: "Nikos",
              updates: [],
            },
          ]),
        ),
      ),
    );
    await page.goto("/platform/status");
    await expect(page.getByTestId("status-console-open")).toContainText("published by Nikos");
    await expect(page.getByRole("button", { name: "Update" })).toBeVisible();
  });
});
