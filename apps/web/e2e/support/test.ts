import { connect } from "node:net";

import { test as base, type Page, type Request } from "@playwright/test";

import { stubApiPort } from "../../playwright.config";

export * from "@playwright/test";

const HYDRATION_TIMEOUT_MS = 15_000;
// A navigation has no timeout of its own (Playwright's `navigationTimeout` is 0), so a
// teardown `goto` to a renderer that cannot unload in time would wait out the whole test.
const TEARDOWN_NAVIGATION_TIMEOUT_MS = 10_000;
// The dev server compiles a route on its first request, prefetches included, which can take
// several seconds on a loaded runner; a stream still open after this is left to be cut.
const SERVER_RENDER_SETTLE_TIMEOUT_MS = 20_000;

/**
 * The page's server renders still streaming: documents and React Server Component
 * payloads (Next sends `RSC: 1` on those). Leaving the page mid-stream closes the socket
 * under the dev server's renderer, which logs "⨯ Error: The destination stream closed
 * early." (seen on Gitea CI, 2026-11-16: a `<Link>` prefetch of /box still compiling when
 * the test reloaded or ended). Before the shared `goto`, `reload` and teardown leave a
 * page, they let these finish (bounded, so a stream that never ends cannot hold a test).
 */
function trackServerRenders(page: Page) {
  const inFlight = new Set<Request>();
  const isServerRender = (request: Request) => request.resourceType() === "document" || request.headers()["rsc"] === "1";
  page.on("request", (request) => {
    if (isServerRender(request)) inFlight.add(request);
  });
  const done = (request: Request) => inFlight.delete(request);
  page.on("requestfinished", done);
  page.on("requestfailed", done);
  return async function settle() {
    const deadline = Date.now() + SERVER_RENDER_SETTLE_TIMEOUT_MS;
    while (inFlight.size > 0 && Date.now() < deadline && !page.isClosed()) {
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
  };
}

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
    const settleServerRenders = trackServerRenders(page);
    page.goto = async (...args: Parameters<Page["goto"]>) => {
      await settleServerRenders();
      const response = await goto(...args);
      await waitForHydration(page);
      return response;
    };
    page.reload = async (...args: Parameters<Page["reload"]>) => {
      await settleServerRenders();
      const response = await reload(...args);
      await waitForHydration(page);
      return response;
    };
    await provide(page);
    // Teardown removes the routes before it closes the page, so a fetch the page fires
    // in that gap (a poll, a refetch on blur) skips the fallback above and is proxied to
    // the closed stub port: the "Failed to proxy … ECONNREFUSED 127.0.0.1:18302" noise
    // in the dev server log. Leaving for about:blank first stops the page's scripts
    // while the routes still answer. It is bounded: a renderer that does not unload in time
    // (the software-rendered 3D figure on a loaded CI runner, 2026-11-16) is left to the
    // context's own close, which ends the page without waiting for it, instead of holding
    // the test until "Tearing down "page" exceeded the test timeout".
    await settleServerRenders();
    await goto("about:blank", { timeout: TEARDOWN_NAVIGATION_TIMEOUT_MS }).catch(() => undefined);
  },
});
