import { expect, test, type Page } from "./support/test";

// ADR-556: palee.app/business sells Palee to boxes and independent coaches.
// A subtle switch picks the audience (?for=coach opens the coach's side),
// «See how it works» opens the day timeline in an overlay, and the page ends
// with a box vs coach comparison. Phones get stories. The API is stubbed.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });

async function guest(page: Page) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
}

test.describe("business landing", () => {
  test.use({ contextOptions: { reducedMotion: "reduce" } });

  test("switches between box and coach, and keeps the choice in the address", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await guest(page);
    await page.goto("/business");

    await expect(page.getByRole("heading", { level: 1, name: "Your box runs on its own. You coach." })).toBeVisible();
    // The switch sits in the middle of the top bar; the phones' one (in the stories) is hidden here.
    const audience = page.getByTestId("business-topbar").getByRole("group", { name: "For" });
    await expect(audience).toBeVisible();
    await audience.getByRole("button", { name: /coach/i }).click();
    await expect(page).toHaveURL(/\/business\?for=coach$/);
    await expect(page.getByRole("heading", { level: 1, name: "Your clients, everywhere. No spreadsheets." })).toBeVisible();

    // Coaches never see what only a box needs.
    await expect(page.getByTestId("business-tile-staffPay")).toHaveCount(0);
    await expect(page.getByTestId("business-tile-cleaning")).toHaveCount(0);
    await expect(page.getByTestId("business-tile-coachAccounting")).toContainText("if you choose");

    await page.reload();
    await expect(page.getByRole("heading", { level: 1, name: "Your clients, everywhere. No spreadsheets." })).toBeVisible();
  });

  test("shows the free website and e-shop, the management tiles and the comparison", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await guest(page);
    await page.goto("/business");

    await expect(page.getByTestId("business-shop")).toContainText("A website and an e-shop, free from day one.");
    await expect(page.getByTestId("business-tile-staffPay")).toBeVisible();
    await expect(page.getByTestId("business-tile-campaigns")).toContainText("Promotion campaigns");
    await expect(page.getByTestId("business-tile-accounting")).toContainText("otherwise one click exports everything for your accountant");

    const compare = page.getByTestId("business-compare");
    await expect(compare.getByRole("row", { name: /Staff pay and allowances/ })).toContainText("Not included");
  });

  test("opens the day timeline from «See how it works» and starts from it", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await guest(page);
    await page.goto("/business");

    await page.getByRole("button", { name: "See how it works" }).click();
    const how = page.getByRole("dialog", { name: "How it works" });
    await expect(how.getByRole("heading", { name: "A day at your box, with Palee" })).toBeVisible();
    await expect(how.getByRole("heading", { name: "The day WOD is ready" })).toBeVisible();
    await how.getByRole("button", { name: "Close" }).click();
    await expect(how).toBeHidden();
  });

  test("plays stories on a phone and reaches the business page from the athletes' landing", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await guest(page);
    await page.goto("/business");

    const stories = page.getByTestId("landing-stories");
    await expect(stories.getByRole("heading", { level: 1, name: "Your box runs on its own." })).toBeVisible();
    await stories.getByRole("button", { name: "Pause" }).click();
    await page.getByTestId("landing-story-stage").click({ position: { x: 300, y: 200 } });
    await expect(stories.getByRole("heading", { name: "A free website" })).toBeVisible();

    await stories.getByRole("button", { name: "Coach" }).click();
    await expect(stories.getByRole("heading", { level: 1, name: "Your clients, everywhere." })).toBeVisible();
  });

  test("the chip beside the logo always points to the other landing, away from sign in", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await guest(page);
    await page.goto("/");

    await page.getByTestId("landing-for-business").click();
    await expect(page).toHaveURL(/\/business$/);
    await expect(page.getByRole("heading", { level: 1, name: "Your box runs on its own. You coach." })).toBeVisible();

    // On the business page the same chip says «For athletes →»; nothing else links there from the top bar.
    const topbar = page.getByTestId("business-topbar");
    await expect(topbar.getByRole("link", { name: /For athletes/ })).toHaveCount(1);
    await topbar.getByTestId("business-for-athletes").click();
    await expect(page.getByTestId("guest-landing")).toBeVisible();
  });
});
