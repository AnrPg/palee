"use client";

import { useSyncExternalStore, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchClubMembers, membersKey, type CommunityClub } from "@/api/community";
import { ClubChannels, ClubPosts, useClubSpace, type ClubSpaceState } from "@/components/community/ClubPage";
import { channelName } from "@/components/community/community";
import { ComposePrompt } from "@/components/community/ComposeSheet";
import { MembersTab } from "@/components/community/MembersTab";
import { useClubRealtime } from "@/components/community/use-community";
import { EventList } from "@/components/events/EventParts";
import { useClubEvents } from "@/components/events/use-events";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { subscribeNever } from "@/lib/maps";
import { useMediaQuery } from "@/lib/use-media-query";

/** Desktop: Tailwind's `lg`, where the side column shows. */
export const DESKTOP_QUERY = "(min-width: 64rem)";
const EVENTS_SHOWN = 3;
const CHANNELS_SHOWN = 6;
const FACES_SHOWN = 5;

// A channel link into the box's club (`/b/<slug>?channel=<id>`, ADR-590).
const readChannel = () => new URLSearchParams(window.location.search).get("channel");
const serverChannel = () => null;

type View = "feed" | "channels" | "members";
const VIEWS: View[] = ["feed", "channels", "members"];
const VIEW_KEYS: Record<View, string> = { feed: "tabFeed", channels: "tabChannels", members: "tabMembers" };

/**
 * ADR-621 (ANR 2026-11-10, layout A): the box's club inside its page, for its
 * members and staff. One level of navigation: «Γράψε κάτι στο club…» over the
 * Ροή and, on desktop, a side column with the next events (they open the
 * page's own «Events» tab), the channels (one opens the Ροή of that channel,
 * «Όλα» the full list) and the club's members. Phones keep a small
 * Ροή · Κανάλια · Μέλη club switch instead of the column.
 */
export function BoxClubTab({ club, clubs, onShowEvents }: { club: CommunityClub; clubs: CommunityClub[]; onShowEvents: () => void }) {
  const t = useTranslations("Clubs");
  const tBox = useTranslations("BoxPage");
  const channel = useSyncExternalStore(subscribeNever, readChannel, serverChannel);
  useClubRealtime(clubs);
  const space = useClubSpace(club.id, club, channel);
  const desktop = useMediaQuery(DESKTOP_QUERY);
  const view: View = space.tab === "events" ? "feed" : space.tab;
  const showView = (next: View) => space.setTab(next);

  const main =
    view === "channels" ? (
      <ClubChannels club={club} onOpen={space.showChannel} />
    ) : view === "members" ? (
      <MembersTab club={club} />
    ) : (
      <>
        <ComposePrompt clubs={clubs} clubId={club.id} channelId={space.openChannel?.id} />
        <ClubPosts club={club} clubs={clubs} space={space} onShowEvents={onShowEvents} boxPage />
      </>
    );

  return (
    <div className="flex flex-col gap-4 lg:grid lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start lg:gap-6" data-testid="box-club-tab">
      <div className="flex min-w-0 flex-col gap-4">
        {desktop ? (
          view === "feed" ? null : (
            <button
              type="button"
              onClick={() => showView("feed")}
              className="flex min-h-10 items-center gap-1 self-start text-sm font-bold"
              style={{ color: "var(--text-soft)" }}
              data-testid="box-club-back"
            >
              <span aria-hidden="true" className="rtl:rotate-180">‹</span>
              {tBox("backToFeed")}
            </button>
          )
        ) : (
          <div role="tablist" aria-label={tBox("clubSectionsAria")} className="inline-flex gap-0.5 self-start rounded-xl p-1" style={{ background: "var(--panel-raised)" }}>
            {VIEWS.map((id) => (
              <button
                key={id}
                type="button"
                role="tab"
                aria-selected={view === id}
                onClick={() => showView(id)}
                className="min-h-9 rounded-lg px-3.5 text-sm font-bold"
                style={view === id ? { background: "var(--panel)", color: "var(--text)", boxShadow: "var(--shadow-sm)" } : { color: "var(--dim)" }}
              >
                {t(VIEW_KEYS[id])}
              </button>
            ))}
          </div>
        )}
        {main}
      </div>
      {desktop ? <SideColumn club={club} space={space} view={view} onShowView={showView} onShowEvents={onShowEvents} /> : null}
    </div>
  );
}

function SideColumn({
  club,
  space,
  view,
  onShowView,
  onShowEvents,
}: {
  club: CommunityClub;
  space: ClubSpaceState;
  view: View;
  onShowView: (view: View) => void;
  onShowEvents: () => void;
}) {
  const t = useTranslations("Clubs");
  const tBox = useTranslations("BoxPage");
  const tCommunity = useTranslations("Community");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const events = useClubEvents(club.id, "upcoming");
  const members = useQuery({ queryKey: membersKey(club.id, ""), enabled: Boolean(token), queryFn: () => fetchClubMembers(token!, club.id, "") });
  const channels = club.channels.filter((entry) => entry.joined && (entry.status ?? "active") === "active");
  const openId = view === "feed" ? (space.openChannel?.id ?? null) : null;
  const upcoming = events.data ?? [];

  return (
    <aside className="sticky top-[calc(var(--top-bar-space,0px)+4.5rem)] flex flex-col gap-4" data-testid="box-club-side">
      {upcoming.length > 0 ? (
        <SideCard title={tBox("clubUpcoming")} more={tBox("seeAll")} onMore={onShowEvents} testId="box-club-side-events">
          <EventList events={upcoming.slice(0, EVENTS_SHOWN)} lead={(event) => event.group?.name ?? undefined} />
        </SideCard>
      ) : null}
      {channels.length > 0 ? (
        <SideCard title={t("tabChannels")} more={tBox("seeAll")} onMore={() => onShowView("channels")} testId="box-club-side-channels">
          <ul className="flex flex-col">
            {channels.slice(0, CHANNELS_SHOWN).map((entry) => (
              <li key={entry.id}>
                <button
                  type="button"
                  onClick={() => {
                    // The open channel again: back to the whole Ροή.
                    if (openId === entry.id) {
                      if (space.posts) space.changePosts({ ...space.posts, channel: [] });
                    } else space.showChannel(entry.id);
                  }}
                  aria-pressed={openId === entry.id}
                  className="flex min-h-10 w-full items-center gap-2 rounded-xl px-2 text-start text-sm"
                  style={openId === entry.id ? { background: "var(--panel-raised)", color: "var(--text)", fontWeight: 800 } : { color: "var(--text-soft)" }}
                >
                  <span aria-hidden="true" className="font-bold" style={{ color: "var(--dim)" }}>#</span>
                  <span className="min-w-0 truncate">{channelName(entry, tCommunity)}</span>
                </button>
              </li>
            ))}
          </ul>
        </SideCard>
      ) : null}
      {members.data && members.data.count > 0 ? (
        <SideCard title={t("tabMembers")} more={tBox("seeAll")} onMore={() => onShowView("members")} testId="box-club-side-members">
          <div className="flex items-center justify-between gap-3">
            <span className="flex">
              {(members.data.members ?? []).slice(0, FACES_SHOWN).map((member, index) => (
                <span key={member.id} className={`rounded-full ${index > 0 ? "-ms-2" : ""}`} style={{ border: "2px solid var(--panel)" }}>
                  <PersonAvatar name={member.nickname} url={member.avatar_url} size={28} />
                </span>
              ))}
            </span>
            <span className="text-sm" style={{ color: "var(--dim)" }}>{t("membersCount", { count: members.data.count })}</span>
          </div>
        </SideCard>
      ) : null}
    </aside>
  );
}

function SideCard({ title, more, onMore, testId, children }: { title: string; more: string; onMore: () => void; testId: string; children: ReactNode }) {
  return (
    <section className="rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid={testId}>
      <div className="mb-2 flex items-baseline justify-between gap-3">
        <h3 className="text-sm font-extrabold" style={{ color: "var(--text)" }}>{title}</h3>
        <button type="button" onClick={onMore} className="text-sm font-bold" style={{ color: "var(--primary-strong, var(--primary))" }}>
          {more} ›
        </button>
      </div>
      {children}
    </section>
  );
}
