import type { Page } from "@playwright/test";

const json = (body: unknown) => ({ status: 200, contentType: "application/json", body: JSON.stringify(body) });

/** A full `PersonProfile` as GET /api/people/:id answers it (ADR-554). */
export function personProfile(overrides: Record<string, unknown> & { id: string }) {
  return {
    nickname: null,
    handle: null,
    avatar_url: null,
    is_me: false,
    private: false,
    followers_count: 0,
    following_count: 0,
    follow_groups: { buddies: 0, followers_only: 0, following_only: 0 },
    my_status: "none",
    follows_me: false,
    buddy: false,
    bio: null,
    tabs: ["media", "posts"],
    box_id: null,
    show_rank: false,
    box: null,
    ...overrides,
  };
}

/**
 * ADR-554: /me renders the owner's profile from GET /api/people/<own id>, so
 * a spec that opens /me stubs it with `is_me` and an empty Media and Posts
 * tab (the catch-all `{}` would leave the page without its ☰ and rank line).
 * Register it after the spec's `**\/api/**` catch-all; later routes win.
 */
export async function stubOwnProfile(page: Page, user: { id: string; nickname?: string | null; handle?: string | null }, overrides: Record<string, unknown> = {}) {
  const profile = personProfile({ id: user.id, nickname: user.nickname ?? null, handle: user.handle ?? null, is_me: true, ...overrides });
  await page.route(`**/api/people/${user.id}`, (route) => route.fulfill(json(profile)));
  await page.route(`**/api/people/${user.id}/media**`, (route) => route.fulfill(json({ posts: [], next_cursor: null })));
  await page.route(`**/api/people/${user.id}/posts**`, (route) => route.fulfill(json({ posts: [], next_cursor: null })));
  return profile;
}
