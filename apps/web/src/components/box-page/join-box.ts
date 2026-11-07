import type { PublicBoxPage } from "@/api/social";

/**
 * ANR 2026-11-07: «Γίνε μέλος box» is on every box page, always the main
 * action for someone who is not a box member yet. It leads to the box's
 * packages when it lists any, else to its member join link when that is on,
 * else to the chat with the box with a «how do I join» message ready, so it
 * never ends in a dead end. Following stays a separate, quieter action.
 */
export function joinBoxHref(page: Pick<PublicBoxPage, "box" | "joining">, signedIn: boolean) {
  const slug = encodeURIComponent(page.box.slug);
  if (page.joining?.packages) return `/b/${slug}/packages`;
  if (page.joining?.join_link) return `/join/${slug}`;
  const chat = `/b/${slug}/chat?draft=member`;
  return signedIn ? chat : `/login?next=${encodeURIComponent(chat)}`;
}
