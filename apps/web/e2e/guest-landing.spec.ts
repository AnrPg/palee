import { expect, test, type Page } from "./support/test";

// ADR-555: palee.app for guests is the landing. Phones get stories (pause
// button, hold to pause); tablets and up one dark screen with the animated
// phone and «See more»; sign in and sign up open over it. /login and
// /register open the form straight away. The API is stubbed.

const json = (body: unknown, status = 200) => ({ status, contentType: "application/json", body: JSON.stringify(body) });
const TAGLINE = "Hey pal, the real PR is coming back πάλι (palee)!";

async function guest(page: Page) {
  await page.context().addCookies([{ name: "palee_locale", value: "en", url: "http://127.0.0.1" }]);
  await page.route("**/api/**", (route) => route.fulfill(json({})));
  await page.route("**/api/auth/refresh", (route) => route.fulfill(json({ error: "unauthorized" }, 401)));
}

test.describe("guest landing", () => {
  test.use({ contextOptions: { reducedMotion: "reduce" } });

  test("shows the landing on / with the tagline and opens sign-up in the drawer", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await guest(page);
    await page.goto("/");

    await expect(page).toHaveURL(/\/$/);
    await expect(page.getByRole("heading", { level: 1, name: "Training bonds the crew." })).toBeVisible();
    await expect(page.getByTestId("palee-tagline").first()).toHaveText(TAGLINE);

    await page.getByRole("button", { name: "See more" }).click();
    await expect(page.getByRole("heading", { name: "Why you'll open it every day" })).toBeInViewport();

    await page.getByRole("button", { name: "Create account" }).first().click();
    const drawer = page.getByRole("dialog", { name: "Sign in or create an account" });
    await expect(drawer.getByLabel("Your name", { exact: true })).toBeVisible();
    await drawer.getByRole("button", { name: "Close" }).click();
    await expect(drawer).toBeHidden();
  });

  test("opens the sign-in form straight away on /login", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await guest(page);
    await page.goto("/login");

    const drawer = page.getByRole("dialog", { name: "Sign in or create an account" });
    await expect(drawer.getByLabel("Email or @handle")).toBeVisible();
    await expect(page.getByRole("button", { name: "Sign in", exact: true })).toHaveCount(1);
  });

  test("plays stories on a phone, with a pause button and a sign-in sheet", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await guest(page);
    await page.goto("/");

    const stories = page.getByTestId("landing-stories");
    await expect(stories.getByRole("heading", { level: 1, name: "Training bonds the crew." })).toBeVisible();
    await stories.getByRole("button", { name: "Pause" }).click();
    await expect(stories.getByText("Paused")).toBeVisible();
    await expect(stories.getByRole("button", { name: "Play" })).toBeVisible();

    await page.getByTestId("landing-story-stage").click({ position: { x: 300, y: 200 } });
    await expect(stories.getByRole("heading", { name: "Every PR, with your crew." })).toBeVisible();

    await stories.getByRole("button", { name: "I already have an account" }).click();
    await expect(page.getByRole("dialog", { name: "Sign in or create an account" }).getByLabel("Email or @handle")).toBeVisible();
  });
});
