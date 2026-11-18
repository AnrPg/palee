import { expect, type APIRequestContext } from "@playwright/test";

// One attempt's own limit: a request the dev server stalls on is dropped and sent
// again on a fresh connection instead of holding the test until its 60 s timeout.
const ATTEMPT_TIMEOUT_MS = 15_000;
const TOTAL_TIMEOUT_MS = 45_000;

/**
 * Asserts that GET `path` answers `status`. Seen on Gitea CI (2026-11-18): after
 * 50 minutes of the full suite, the dev server never answered one plain
 * `request.get` (/.well-known/assetlinks.json, a 4 ms route when fresh) and the
 * test timed out with "Request context disposed". Each attempt here has its own
 * timeout, a stalled or failed attempt is retried, and a wrong status still fails.
 */
export async function expectStatus(request: APIRequestContext, path: string, status: number) {
  await expect
    .poll(
      async () => {
        try {
          return (await request.get(path, { timeout: ATTEMPT_TIMEOUT_MS, maxRedirects: 0 })).status();
        } catch (error) {
          return `no answer: ${error instanceof Error ? error.message.split("\n")[0] : String(error)}`;
        }
      },
      { message: `GET ${path}`, timeout: TOTAL_TIMEOUT_MS, intervals: [500, 1_000, 2_000] },
    )
    .toBe(status);
}
