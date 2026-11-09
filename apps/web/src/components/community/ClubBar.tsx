"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import type { CommunityClub } from "@/api/community";
import { fetchFollowing, SOCIAL_KEY, type FollowEntry } from "@/api/social";
import { clubHref, clubInitials } from "@/components/community/community";
import { NavIcon } from "@/components/nav/NavIcons";
import { useSession } from "@/components/session-provider";

/** ADR-590 §3: the first page of boxes the person follows (the bar shows them after their clubs). */
export const FOLLOWED_BOXES_KEY = [...SOCIAL_KEY, "following-bar", "organization"] as const;

/**
 * Boxes followed (accepted) whose club is not already in the bar, i.e. boxes
 * the person follows without being a member or staff there.
 */
export function followedBoxBubbles(entries: FollowEntry[], clubs: Pick<CommunityClub, "kind" | "organization_id">[]) {
  const inBar = new Set(clubs.filter((club) => club.kind === "gym").map((club) => club.organization_id));
  return entries.flatMap((entry) =>
    entry.box && entry.status === "active" && !inBar.has(entry.box.organization_id) ? [entry.box] : [],
  );
}

/**
 * The club bar (vision §7.1): Όλα, then one bubble per club (a bubble opens
 * the club page), then a dashed bubble per box the person follows without
 * belonging to it (ADR-590, opens the box page), then «Βρες» (a magnifying
 * glass) for open clubs, groups and people (board 7 Q7).
 */
export function ClubBar({
  clubs,
  activeClubId,
  findActive = false,
}: {
  clubs: CommunityClub[];
  activeClubId?: string | null;
  findActive?: boolean;
}) {
  const t = useTranslations("Community");
  const tClubs = useTranslations("Clubs");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const following = useQuery({
    queryKey: FOLLOWED_BOXES_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchFollowing(token!, "organization"),
    staleTime: 60_000,
  });
  const followed = followedBoxBubbles(following.data?.entries ?? [], clubs);
  return (
    // A horizontal scroller clips vertically too: py-1.5 leaves room for the
    // active ring (2px outline + 2px offset) so no bubble is cut.
    <nav aria-label={t("clubBar")} className="-mx-4 overflow-x-auto px-4 py-1.5">
      <ul className="flex gap-3">
        <Bubble href="/" label={t("all")} initials={t("allShort")} active={!activeClubId && !findActive} />
        {clubs.map((club) => (
          <Bubble
            key={club.id}
            href={clubHref(club)}
            label={club.name}
            initials={clubInitials(club.name)}
            logo={club.logo_url}
            active={club.id === activeClubId}
          />
        ))}
        {followed.map((box) => (
          <Bubble
            key={box.organization_id}
            href={`/b/${encodeURIComponent(box.slug)}`}
            label={box.name}
            initials={clubInitials(box.name)}
            logo={box.logo_url}
            active={false}
            followed
            testId="club-bar-followed-box"
          />
        ))}
        <Bubble href="/clubs/find" label={tClubs("find")} initials={<NavIcon name="search" size={22} strokeWidth={2} />} active={findActive} dashed />
      </ul>
    </nav>
  );
}

function Bubble({
  href,
  label,
  initials,
  logo,
  active,
  dashed,
  followed,
  testId,
}: {
  href: string;
  label: string;
  initials: ReactNode;
  logo?: string | null;
  active: boolean;
  dashed?: boolean;
  /** ADR-590: a box followed, not joined: a dashed ring in the accent. */
  followed?: boolean;
  testId?: string;
}) {
  return (
    <li className="shrink-0">
      <Link href={href} data-testid={testId} aria-current={active ? "page" : undefined} className="flex w-16 flex-col items-center gap-1">
        <span
          className="flex h-14 w-14 items-center justify-center overflow-hidden rounded-full text-sm font-extrabold"
          style={{
            background: "var(--panel-raised)",
            color: "var(--text)",
            outline: active
              ? "2px solid var(--primary)"
              : followed
                ? "1.5px dashed var(--primary)"
                : `1px ${dashed ? "dashed" : "solid"} var(--border)`,
            outlineOffset: 2,
          }}
        >
          {logo ? (
            // eslint-disable-next-line @next/next/no-img-element -- gym-uploaded media origin
            <img src={logo} alt="" className="h-full w-full object-cover" />
          ) : (
            initials
          )}
        </span>
        <span className="w-full truncate text-center text-xs" style={{ color: active ? "var(--text)" : "var(--dim)" }}>
          {label}
        </span>
      </Link>
    </li>
  );
}
