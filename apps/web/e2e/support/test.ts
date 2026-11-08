import { connect } from "node:net";

import { test as base, type Page } from "@playwright/test";

import { stubApiPort } from "../../playwright.config";

export * from "@playwright/test";

const HYDRATION_TIMEOUT_MS = 15_000;

/** Whether a spec has its stub API server (playwright.config's `stubApiPort`) up right now. */
function stubApiListening(): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = connect({ host: "127.0.0.1", port: stubApiPort });
    socket.once("connect", () => {
      socket.destroy();
      resolve(true);
    });
    socket.once("error", () => resolve(false));
  });
}

/** Waits for the root layout's HydrationMarker; pages without the app shell just move on. */
async function waitForHydration(page: Page) {
  await page
    .waitForFunction(() => document.documentElement.dataset.hydrated === "true", undefined, { timeout: HYDRATION_TIMEOUT_MS })
    .catch(() => undefined);
}

/**
 * The shared `test`: a quiet browser context (below), and `page.goto` and `page.reload` resolve only once React has
 * hydrated the page, so a first tap is never lost on server-rendered HTML
 * (the cause of the intermittent "New entry" / "+ New PR" failures in CI).
 */
export const test = base.extend({
  context: async ({ context }, provide) => {
    // `serviceWorkers: "block"` replaces `register` with one that resolves to
    // nothing and logs a warning each time; keep the same answer, without the warning.
    await context.addInitScript(() => {
      const container = navigator.serviceWorker;
      if (!container) return;
      container.register = async () => undefined as unknown as ServiceWorkerRegistration;
    });
    // Lowest-priority fallback (page routes and later routes win): an API call
    // a spec does not stub goes to the spec's stub API server when one is up,
    // and otherwise answers 404 here instead of being proxied to a closed port
    // (an ECONNREFUSED stack trace in the dev server log).
    await context.route("**/api/**", async (route) => {
      if (await stubApiListening()) return route.continue();
      return route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ error: "not_stubbed" }) });
    });
    await provide(context);
  },
  page: async ({ page }, provide) => {
    const goto = page.goto.bind(page);
    const reload = page.reload.bind(page);
    page.goto = async (...args: Parameters<Page["goto"]>) => {
      const response = await goto(...args);
      await waitForHydration(page);
      return response;
    };
    page.reload = async (...args: Parameters<Page["reload"]>) => {
      const response = await reload(...args);
      await waitForHydration(page);
      return response;
    };
    await provide(page);
    // Teardown removes the routes before it closes the page, so a fetch the page fires
    // in that gap (a poll, a refetch on blur) skips the fallback above and is proxied to
    // the closed stub port: the "Failed to proxy … ECONNREFUSED 127.0.0.1:18302" noise
    // in the dev server log. Leaving for about:blank first stops the page's scripts
    // while the routes still answer.
    await goto("about:blank").catch(() => undefined);
  },
});
