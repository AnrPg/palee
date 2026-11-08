import type { PublicBoxPage } from "@/api/social";

export type JoinBoxTarget = { kind: "link"; href: string } | { kind: "ask" };

/**
 * ANR 2026-11-07 (ADR-552): «Γίνε μέλος box» is on every box page, always the
 * main action for someone who is not a box member yet, and never a dead end.
 * It leads to the box's packages when it lists any (buying makes you a box
 * member), else to its member join link when that is on, else to
 * «Ζήτα να γίνεις μέλος», which the box's staff accept (after signing in).
 * Following stays a separate, quieter action.
 */
export function joinBoxTarget(page: Pick<PublicBoxPage, "box" | "joining">, signedIn: boolean, shownPackages: number | null = null): JoinBoxTarget {
  const slug = encodeURIComponent(page.box.slug);
  // ADR-553: the box chooses who sees its packages; signed in, the count is
  // what this person sees (`shownPackages`), else what everyone sees.
  const packages = shownPackages === null ? page.joining?.packages : shownPackages > 0;
  if (packages) return { kind: "link", href: `/b/${slug}/packages` };
  if (page.joining?.join_link) return { kind: "link", href: `/join/${slug}` };
  if (signedIn) return { kind: "ask" };
  return { kind: "link", href: `/login?next=${encodeURIComponent(`/b/${slug}?join=1`)}` };
}
