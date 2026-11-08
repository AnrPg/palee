"use client";

import Link from "next/link";
import { type ReactNode } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchProfilePRs } from "@/api/gamification";
import { fetchPRsSharedWithMe } from "@/api/pr-sharing";
import { fetchPerson, fetchPersonPosts, personKey, type PersonProfile as Person } from "@/api/social";
import { MyRanksCard } from "@/components/body-devices/MyRanksCard";
import { PostCard } from "@/components/community/PostCard";
import { MessageButton } from "@/components/conversations/MessageButton";
import { MeSheetButton } from "@/components/member-app/me/MeSheet";
import { SharedPRCard } from "@/components/pantheon/SharedPRsSection";
import { useSession } from "@/components/session-provider";
import { FollowButton } from "@/components/social/FollowButton";
import { MediaGrid } from "@/components/social/MediaGrid";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { AddTabButton, EditProfileButton, ShareProfileButton } from "@/components/social/ProfileActions";
import { ProfileBadges } from "@/components/social/ProfileBadges";
import { BuddyBadge, LockedNote } from "@/components/social/SocialBits";
import { countsParts, personTab, postsLockKey, profileTabs, type PersonTab } from "@/components/social/social-model";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useSelectedMembershipRole } from "@/lib/membership-role";

/**
 * A person's profile, and Εγώ, which is the same page for its owner (ADR-554,
 * mockup «1A 2A 3C»): an Instagram-like header (avatar, name and three
 * counts, «Λίγα λόγια», two quiet buttons), then the tabs, «Πολυμέσα ·
 * Αναρτήσεις» first and the optional ones the owner added with «+». What you
 * see on your own profile is what others see; only the ☰ (`MeSheet`), the «+»
 * and your own rank line are yours alone.
 */
export function PersonProfile({ id }: { id: string }) {
  const t = useTranslations("Social");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const person = useQuery({ queryKey: personKey(id), enabled: Boolean(token), queryFn: () => fetchPerson(token!, id) });

  if (person.isPending) return <main className="mx-auto w-full max-w-xl p-4" style={{ color: "var(--dim)" }}>{t("loading")}</main>;
  if (!person.data)
    return (
      <main className="mx-auto w-full max-w-xl p-4">
        <ErrorNotice>{t("personMissing")}</ErrorNotice>
      </main>
    );
  return <Profile profile={person.data} />;
}

function Profile({ profile }: { profile: Person }) {
  const t = useTranslations("Social");
  const router = useRouter();
  const params = useSearchParams();
  const tabs = profileTabs(profile.tabs);
  const tab = personTab(params.get("tab"), tabs);
  const mine = profile.is_me;
  const base = mine ? "/me" : `/people/${profile.id}`;

  return (
    <main className="mx-auto flex w-full max-w-xl flex-col pb-6" data-testid="person-profile">
      <div className="flex min-h-13 items-center gap-2 px-4 pt-3">
        <h1 className="min-w-0 grow truncate text-lg font-extrabold" style={{ color: "var(--text)" }}>
          {profile.private ? <PadlockMark label={t("privateAccount")} /> : null}
          {profile.handle ?? profile.nickname ?? "?"}
        </h1>
        {mine ? <MeSheetButton /> : null}
      </div>

      <ProfileHeader profile={profile} />

      {mine ? <OwnRankLine /> : null}

      <div role="tablist" aria-label={t("profileTabs")} className="mt-3 flex gap-1 px-2">
        {tabs.map((value) => (
          <button
            key={value}
            type="button"
            role="tab"
            id={`profile-tab-${value}`}
            aria-selected={tab === value}
            aria-controls="profile-tabpanel"
            aria-label={t(`personTab.${value}`)}
            onClick={() => router.replace(`${base}?tab=${value}`, { scroll: false })}
            className="@container flex min-h-12 min-w-0 flex-1 flex-col items-center justify-center gap-0.5 text-[11px] font-bold"
            style={{ color: tab === value ? "var(--text)" : "var(--dim)" }}
          >
            <TabIcon tab={value} />
            {/* The label goes when a tab gets narrower than ~62px; the icon stays, named by aria-label. */}
            <span aria-hidden="true" className="max-w-full truncate @max-[3.875rem]:hidden">
              {t(`personTab.${value}`)}
            </span>
          </button>
        ))}
        {mine ? <AddTabButton profile={profile} tabs={tabs} /> : null}
      </div>

      <div role="tabpanel" id="profile-tabpanel" aria-labelledby={`profile-tab-${tab}`} className="mt-2 flex flex-col gap-3">
        {tab === "media" ? <MediaGrid personId={profile.id} lock={postsLockKey(profile)} mine={mine} /> : null}
        {tab === "posts" ? <Posts profile={profile} /> : null}
        {tab === "prs" ? <Prs profile={profile} /> : null}
        {tab === "badges" ? <ProfileBadges profile={profile} /> : null}
      </div>
    </main>
  );
}

/**
 * ADR-554 header, Instagram-like, laid out by its own width (a container
 * query, so it also adapts inside a wide window): avatar | three counts with
 * the name below; under ~300px the name moves next to the avatar and the
 * counts take a full-width row of their own. Sizes scale with the width.
 */
function ProfileHeader({ profile }: { profile: Person }) {
  const t = useTranslations("Social");
  const mine = profile.is_me;

  return (
    <header className="@container flex flex-col px-4 pt-2">
      <div className="grid grid-cols-[auto_minmax(0,1fr)] items-center gap-x-[clamp(0.625rem,5cqi,1.25rem)] gap-y-1.5 [grid-template-areas:'avatar_counts''name_name'] @max-[18.75rem]:[grid-template-areas:'avatar_name''counts_counts']">
        <div className="[grid-area:avatar] size-[clamp(3.5rem,22cqi,5.375rem)]">
          <PersonAvatar name={profile.nickname} url={profile.avatar_url} size="fill" />
        </div>
        <div className="min-w-0 [grid-area:name]">
          <p className="truncate text-[15px] font-extrabold" style={{ color: "var(--text)" }}>{profile.nickname ?? profile.handle ?? "?"}</p>
          {mine ? null : profile.buddy ? (
            <BuddyBadge />
          ) : profile.follows_me ? (
            <span className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{t("followsYou")}</span>
          ) : null}
        </div>
        <Stats profile={profile} />
      </div>

      {profile.bio ? (
        <p className="mt-1 whitespace-pre-line break-words text-sm" style={{ color: "var(--text)" }} data-testid="profile-bio">
          {profile.bio}
        </p>
      ) : null}

      <div className="mt-3 grid grid-cols-2 gap-1.5">
        {mine ? (
          <>
            <EditProfileButton profile={profile} />
            <ShareProfileButton profile={profile} />
          </>
        ) : (
          <>
            <FollowButton
              targetType="user"
              targetId={profile.id}
              initialStatus={profile.my_status}
              followsMe={profile.follows_me}
              buddy={profile.buddy}
              compact
            />
            <MessageButton personId={profile.id} name={profile.nickname} compact />
          </>
        )}
      </div>
    </header>
  );
}

/** The three counts, never overlapping (ADR-193 §1); yours open your Connections. */
function Stats({ profile }: { profile: Person }) {
  const t = useTranslations("Social");
  const mine = profile.is_me;
  return (
    <ul
      aria-label={t("profileCounts")}
      className="grid min-w-0 grid-cols-3 text-center [grid-area:counts] @max-[18.75rem]:border-y @max-[18.75rem]:py-1.5"
      style={{ borderColor: "var(--border)" }}
    >
      {countsParts(profile.follow_groups, mine).map((part, index) => {
        const body = (
          <>
            <span className="block text-[clamp(0.9375rem,5cqi,1.125rem)] font-extrabold leading-tight tabular-nums" style={{ color: "var(--text)" }}>
              {part.count}
            </span>
            <span className="block truncate px-0.5 text-[clamp(0.6875rem,3.3cqi,0.8125rem)] leading-tight @max-[15.625rem]:whitespace-normal" style={{ color: "var(--dim)" }}>
              {t(`stat.${part.key}`, { count: part.count })}
            </span>
          </>
        );
        return (
          <li key={part.tab} className={`min-w-0 ${index > 0 ? "@max-[18.75rem]:border-l" : ""}`} style={{ borderColor: "var(--border)" }}>
            {mine ? (
              <Link href={`/me/connections?tab=${part.tab}`} className="flex min-h-11 flex-col justify-center">
                {body}
              </Link>
            ) : (
              <span className="flex min-h-11 flex-col justify-center">{body}</span>
            )}
          </li>
        );
      })}
    </ul>
  );
}

/** ADR-400: your rank line, only on your own profile until ranks get an audience of their own. */
function OwnRankLine() {
  const { membership } = useSelectedMembershipRole();
  if (!membership) return null;
  return (
    <div className="px-4 pt-3">
      <MyRanksCard slug={membership.organization.slug} />
    </div>
  );
}

function Posts({ profile }: { profile: Person }) {
  const t = useTranslations("Social");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const posts = useInfiniteQuery({
    queryKey: [...personKey(profile.id), "posts"],
    enabled: Boolean(token),
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchPersonPosts(token!, profile.id, pageParam),
    getNextPageParam: (page) => page.next_cursor ?? null,
  });
  const list = posts.data?.pages.flatMap((page) => page.posts) ?? [];
  const lock = postsLockKey(profile);

  return (
    <div className="flex flex-col gap-3 px-4">
      {posts.isSuccess && list.length === 0 && !lock ? <Empty text={t("personPostsEmpty")} /> : null}
      {list.map((post) => (
        <PostCard key={post.id} post={post} />
      ))}
      {posts.hasNextPage ? (
        <button
          type="button"
          onClick={() => void posts.fetchNextPage()}
          className="min-h-11 rounded-2xl text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("more")}
        </button>
      ) : null}
      {lock ? <LockedNote textKey={lock} /> : null}
    </div>
  );
}

/**
 * The PRs they show the people who follow them (ADR-196), plus any they share
 * with you (ADR-129). On your own profile, exactly what your followers see.
 */
function Prs({ profile }: { profile: Person }) {
  const t = useTranslations("Social");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const shared = useQuery({
    queryKey: ["pr-sharing", "shared-with-me"],
    enabled: Boolean(token) && !profile.is_me,
    queryFn: () => fetchPRsSharedWithMe(token!),
  });
  const onProfile = useQuery({
    queryKey: ["prs", "profile", profile.id],
    enabled: Boolean(token),
    queryFn: () => fetchProfilePRs(token!, profile.id),
  });
  if ((!profile.is_me && shared.isPending) || onProfile.isPending) return <p className="px-4" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  const collection = shared.data?.shared.find((entry) => entry.owner.id === profile.id);
  const granted = collection?.prs ?? [];
  const prs = [...granted, ...(onProfile.data ?? []).filter((pr) => !granted.some((own) => own.id === pr.id)).map((pr) => ({ ...pr, history: [] }))];
  const lock = profile.is_me ? null : postsLockKey(profile);

  return (
    <div className="flex flex-col gap-2 px-4">
      {prs.map((pr) => (
        <SharedPRCard key={pr.id} pr={pr} />
      ))}
      {prs.length === 0 && !lock ? <Empty text={profile.is_me ? t("myPrsNoneShown") : t("prsNone")} /> : null}
      {prs.length === 0 && lock ? <LockedNote textKey={lock} /> : null}
      {profile.is_me ? (
        <Link href="/me/sharing#profile-prs" className="text-xs underline" style={{ color: "var(--dim)" }}>
          {t("myPrsWho")}
        </Link>
      ) : null}
    </div>
  );
}

function Empty({ text }: { text: string }) {
  return (
    <p className="rounded-3xl p-5 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
      {text}
    </p>
  );
}

function PadlockMark({ label }: { label: string }) {
  return (
    <svg role="img" aria-label={label} width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" className="mr-1 inline-block align-[-1px]">
      <rect width="14" height="10" x="5" y="11" rx="2" />
      <path d="M8 11V7a4 4 0 0 1 8 0v4" />
    </svg>
  );
}

const TAB_PATHS: Record<PersonTab, ReactNode> = {
  media: (
    <>
      <rect x="3" y="3" width="18" height="18" rx="2" />
      <path d="M9 3v18M15 3v18M3 9h18M3 15h18" />
    </>
  ),
  posts: (
    <>
      <rect x="4" y="3" width="16" height="18" rx="2" />
      <path d="M8 8h8M8 12h8M8 16h5" />
    </>
  ),
  prs: <path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0V4ZM7 6H4a3 3 0 0 0 3 4M17 6h3a3 3 0 0 1-3 4" />,
  badges: (
    <>
      <circle cx="12" cy="14" r="6" />
      <path d="M9 3l3 5 3-5" />
    </>
  ),
};

function TabIcon({ tab }: { tab: PersonTab }) {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="shrink-0">
      {TAB_PATHS[tab]}
    </svg>
  );
}
