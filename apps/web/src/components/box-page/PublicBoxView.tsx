"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, useSyncExternalStore, type CSSProperties, type ReactNode, type RefObject } from "react";
import { useTranslations } from "next-intl";

import type { PublicSite } from "@/api/box-site";
import type { PublicBoxPage } from "@/api/social";
import { SiteConsentProvider } from "@/components/box-site/SiteConsent";
import { SiteLanguageSwitch } from "@/components/box-site/SiteLanguageSwitch";
import { SiteProgrammesNavLink } from "@/components/box-site/SiteProgrammes";
import { SiteRequestSheet } from "@/components/box-site/SiteRequestSheet";
import { SiteSections } from "@/components/box-site/SiteSections";
import { useMyClubs } from "@/components/community/use-community";
import { ClubEventsTab } from "@/components/events/ClubEventsTab";
import { BOTTOM_NAV_SPACE, useBottomTabBarVisible } from "@/components/nav/BottomNav";
import { useSession } from "@/components/session-provider";
import { FollowButton } from "@/components/social/FollowButton";
import { TrialButton } from "@/components/trials/TrialButton";
import { mapsUrl, readApple, serverApple, subscribeNever } from "@/lib/maps";
import { siteBasePath, type SiteLanguage } from "@/lib/public-site";

import { EnquiryCard } from "@/components/leads/LeadEnquiryForm";

import { AboutTab, OpeningHours, type AboutPart } from "./AboutTab";
import { BoxBento, type BentoItem } from "./BoxBento";
import { BoxClubTab } from "./BoxClubTab";
import { BoxEvents } from "./BoxEvents";
import { BoxPosts } from "./BoxPosts";
import { FollowerInviteNotice } from "./FollowerInviteNotice";
import { GuestBanner } from "./GuestBanner";
import { JoinBoxAction } from "./JoinBoxAction";
import { boxChatHref } from "@/components/trials/box-chat-links";

import { Icon } from "./Icon";
import { LockedTab } from "./LockedTab";
import { PhotoViewer } from "./PhotoViewer";
import { VisitorSchedule } from "./VisitorSchedule";

const PlacesMap = dynamic(() => import("@/components/member-app/box/schedule/PlacesMap"), {
  ssr: false,
  loading: () => <div className="h-full w-full animate-pulse" style={{ background: "var(--panel-raised)" }} />,
});

// ADR-590: «Club» shows only to the box's members and staff, first, and opens by default for them.
const TABS = ["club", "about", "schedule", "events", "posts"] as const;
type Tab = (typeof TABS)[number];

/** The tab the hash names, else the default: the club for its members, «Σχετικά» for everyone else. */
export function boxTab(hash: string, member: boolean): Tab {
  const named = TABS.find((value) => value === hash);
  if (named && (named !== "club" || member)) return named;
  return member ? "club" : "about";
}

// The open tab lives in the URL hash (#schedule) so a shared link and the
// way back from sign-in land on it.
function subscribeHash(onChange: () => void) {
  window.addEventListener("hashchange", onChange);
  return () => window.removeEventListener("hashchange", onChange);
}
const readHash = () => window.location.hash.slice(1);
const serverHash = () => "";

/**
 * Whether the box's name and actions have scrolled up out of view, so the
 * sticky bar carries them on desktop (ANR 2026-11-09). False on the server.
 */
function useScrolledPast(ref: RefObject<HTMLElement | null>) {
  const [past, setPast] = useState(false);
  useEffect(() => {
    const node = ref.current;
    if (!node || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(([entry]) => setPast(Boolean(entry && !entry.isIntersecting && entry.boundingClientRect.top < 0)));
    observer.observe(node);
    return () => observer.disconnect();
  }, [ref]);
  return past;
}

/**
 * The public box page (ADR-142; plan §5a board 4, board 5 Q1–Q2). Phones:
 * cover, logo and name, sticky tabs, and a fixed bottom bar with the actions.
 * Desktop (ANR 2026-11-09, layout C): the cover inside the page's 1200 px,
 * rounded; logo, name and the actions in one row under it; a sticky bar with
 * the tabs that also carries the box and its main action once the header
 * scrolls away; then «bento» cards in two columns, with the map, address and
 * hours on top of the right one.
 */
export function PublicBoxView({
  page,
  site = null,
  standalone = false,
  language = "box",
}: {
  page: PublicBoxPage;
  /** ADR-388: the box's website, when the owner switched it on; its sections become «Σχετικά». */
  site?: PublicSite | null;
  /** On the box's own domain: the website alone, without the app's tabs and back button. */
  standalone?: boolean;
  language?: SiteLanguage;
}) {
  if (!site) return <BoxView page={page} site={null} standalone={false} language="box" />;
  return (
    <SiteConsentProvider slug={page.box.slug} site={site}>
      <BoxView page={page} site={site} standalone={standalone} language={language} />
    </SiteConsentProvider>
  );
}

function BoxView({ page, site, standalone, language }: { page: PublicBoxPage; site: PublicSite | null; standalone: boolean; language: SiteLanguage }) {
  const t = useTranslations("BoxPage");
  const router = useRouter();
  const { status, tokens } = useSession();
  const clubs = useMyClubs();
  const tabBar = useBottomTabBarVisible();
  const hash = useSyncExternalStore(subscribeHash, readHash, serverHash);
  const tabsRef = useRef<HTMLDivElement>(null);
  const identityRef = useRef<HTMLDivElement>(null);
  const stuck = useScrolledPast(identityRef);
  const [viewer, setViewer] = useState<number | null>(null);
  const [copied, setCopied] = useState(false);
  const [request, setRequest] = useState<"trial" | "contact" | null>(null);
  const basePath = siteBasePath(page.box.slug, standalone);

  const signedIn = status === "authenticated" && Boolean(tokens?.access_token);
  const club = clubs.data?.find((entry) => entry.kind === "gym" && entry.organization_id === page.box.organization_id) ?? null;
  const member = Boolean(club) && !standalone;
  const tab = boxTab(hash, member);
  const tabs = TABS.filter((value) => value !== "club" || member);
  const photos = [...(page.profile.cover ? [page.profile.cover] : []), ...page.profile.photos];
  const place = page.locations.find((location) => location.neighbourhood || location.city);
  const line = place?.neighbourhood ?? place?.city ?? null;
  const firstHours = page.locations.find((location) => (location.opening_hours ?? []).length > 0);
  const apple = useSyncExternalStore(subscribeNever, readApple, serverApple);
  const pinned = page.locations.find((location) => location.latitude != null && location.longitude != null);

  function select(next: Tab) {
    const fallback = member ? "club" : "about";
    window.history.replaceState(null, "", next === fallback ? window.location.pathname + window.location.search : `#${next}`);
    window.dispatchEvent(new HashChangeEvent("hashchange"));
    const top = tabsRef.current?.getBoundingClientRect().top ?? 1;
    if (top <= 1) tabsRef.current?.scrollIntoView({ block: "start" });
  }

  async function share() {
    const url = window.location.origin + (standalone ? "/" : `/b/${page.box.slug}`);
    if (navigator.share) {
      try {
        await navigator.share({ title: page.box.name, url });
      } catch {
        // The visitor closed the share sheet.
      }
      return;
    }
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  }

  function back() {
    if (window.history.length > 1) router.back();
    else router.push("/");
  }

  const siteTrial = site?.forms.trial ? () => setRequest("trial") : null;
  const actions = standalone ? (
    <SiteActions site={site!} onRequest={setRequest} />
  ) : (
    <Actions
      page={page}
      token={signedIn ? tokens!.access_token : null}
      loading={status === "loading" || (signedIn && clubs.isPending)}
      clubId={club?.id ?? null}
      onGuestTrial={siteTrial}
      onShare={() => void share()}
    />
  );
  // Desktop: the card on top of the right column (map, address, hours).
  const info = <InfoCard page={page} apple={apple} pinned={pinned} firstHours={firstHours} onAddress={() => select("about")} />;
  const sections = site ? (
    <SiteSections page={page} site={site} language={language} basePath={basePath} onOpenPhoto={setViewer} onRequest={setRequest} aside={info} />
  ) : null;
  const roundButtonClass = "grid h-10 w-10 place-items-center rounded-full";
  const desktopActions = standalone ? (
    <SiteActions site={site!} onRequest={setRequest} />
  ) : (
    <Actions
      page={page}
      token={signedIn ? tokens!.access_token : null}
      loading={status === "loading" || (signedIn && clubs.isPending)}
      clubId={club?.id ?? null}
      onGuestTrial={siteTrial}
      onShare={() => void share()}
      row
    />
  );

  return (
    <div className="w-full">
      <header className="relative">
        {/* Phones: the cover runs edge to edge. Desktop (ANR 2026-11-09): it sits inside the page's width, rounded. */}
        <div className="lg:mx-auto lg:max-w-[75rem] lg:px-6 lg:pt-6">
          <div
            // ADR-621: the tall cover is the «Σχετικά» showcase; the other tabs get a strip so their content starts high.
            className={`relative h-52 w-full overflow-hidden sm:h-64 lg:rounded-[2rem] ${standalone || tab === "about" ? "lg:h-80" : "lg:h-36"}`}
            style={{ background: "linear-gradient(135deg, var(--deep), var(--primary))" }}
          >
            {page.profile.cover ? (
              <button type="button" onClick={() => setViewer(0)} aria-label={t("openPhotos")} className="block h-full w-full">
                {/* eslint-disable-next-line @next/next/no-img-element -- media from the gym's storage */}
                <img src={page.profile.cover.url} alt="" className="h-full w-full object-cover" />
              </button>
            ) : null}
            <div className="absolute inset-x-0 top-0 flex justify-between p-3 pt-[max(0.75rem,env(safe-area-inset-top))] lg:p-5">
              {standalone ? (
                <span />
              ) : (
                <button type="button" onClick={back} aria-label={t("back")} className={`${roundButtonClass} rtl:rotate-180`} style={{ background: "var(--media-control)", color: "var(--on-media)" }}>
                  <Icon name="chevron-left" />
                </button>
              )}
              <span className="flex gap-2">
                {site && (standalone || status === "guest") ? <SiteLanguageSwitch slug={page.box.slug} boxLanguage={site.language} languages={site.languages} language={language} basePath={basePath} /> : null}
                {photos.length > 1 ? (
                  <button type="button" onClick={() => setViewer(0)} aria-label={t("openPhotos")} className={roundButtonClass} style={{ background: "var(--media-control)", color: "var(--on-media)" }}>
                    <Icon name="images" />
                  </button>
                ) : null}
                <button type="button" onClick={() => void share()} aria-label={t("share")} className={`${roundButtonClass} ${member ? "lg:hidden" : ""}`} style={{ background: "var(--media-control)", color: "var(--on-media)" }}>
                  <Icon name={copied ? "check" : "share"} />
                </button>
              </span>
            </div>
          </div>
        </div>
        <span role="status" className="sr-only">{copied ? t("linkCopied") : ""}</span>
        <div ref={identityRef} className="mx-auto flex max-w-[75rem] flex-col gap-1 px-4 lg:flex-row lg:items-end lg:gap-5 lg:px-12">
          <Logo page={page} className="-mt-10 lg:-mt-16" size={80} desktopSize={120} />
          <div className="min-w-0 lg:flex-1 lg:pb-2">
            <h1 className="mt-2 text-2xl font-extrabold lg:text-4xl lg:tracking-tight" style={{ color: "var(--text)" }}>{page.box.name}</h1>
            {line || member ? (
              <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm lg:mt-1 lg:text-base" style={{ color: "var(--text-soft)" }}>
                {line ? <span>{line}</span> : null}
                {/* ADR-621: who you are here, once, quietly (instead of «Μέλος του club» over the club). */}
                {member && club ? (
                  <span className="rounded-full px-2.5 py-0.5 text-xs font-bold" style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }} data-testid="box-page-role">
                    {club.role === "staff" ? t("staffBadge") : t("memberBadge")}
                  </span>
                ) : null}
              </p>
            ) : null}
          </div>
          {standalone || tab === "about" ? (
            <div className="lg:pb-2">
              <SiteProgrammesNavLink site={site} />
            </div>
          ) : null}
          {/* Members have no fixed bar on phones: their one action (Μήνυμα) sits here on every screen. */}
          <div className={`${member ? "mt-3 lg:mt-0" : "hidden"} lg:block lg:pb-2`} data-testid="box-page-header-actions">{desktopActions}</div>
        </div>
      </header>

      {!standalone && signedIn && !club && !clubs.isPending ? (
        <div className="mx-auto max-w-[75rem] lg:mt-6 lg:px-6">
          {/* ADR-580: the box invited this follower to become a box member. */}
          <FollowerInviteNotice token={tokens!.access_token} slug={page.box.slug} />
          <GuestBanner token={tokens!.access_token} box={page.box} />
        </div>
      ) : null}

      <div className="mx-auto max-w-[75rem] lg:mt-6 lg:px-6">
        {standalone ? (
          <section className="px-4 pb-8 pt-5 lg:px-0">{sections}</section>
        ) : (
          <>
            {/* Sticky bar: the tabs; on desktop, once the header scrolls away, also the
                box's logo and name and its main action (ANR 2026-11-09, Q2). */}
            <div
              ref={tabsRef}
              className="sticky top-(--top-bar-space) z-(--z-sticky) mt-4 flex items-center gap-3 px-4 pb-2 pt-[max(0.5rem,env(safe-area-inset-top))] transition-[top] duration-300 motion-reduce:transition-none lg:mt-0 lg:px-0"
              style={{ background: "var(--bg)", borderBottom: stuck ? "1px solid var(--border)" : "1px solid transparent" }}
              data-stuck={stuck || undefined}
            >
              {stuck ? (
                <span className="hidden min-w-0 shrink items-center gap-2.5 lg:flex" data-testid="box-page-bar-identity">
                  <Logo page={page} size={32} bare />
                  <b className="truncate text-sm" style={{ color: "var(--text)" }}>{page.box.name}</b>
                </span>
              ) : null}
              <div role="tablist" aria-label={t("tabsAria")} className="flex min-w-0 gap-1 overflow-x-auto">
                {tabs.map((value) => (
                  <button
                    key={value}
                    type="button"
                    role="tab"
                    id={`box-tab-${value}`}
                    aria-selected={tab === value}
                    aria-controls="box-tabpanel"
                    onClick={() => select(value)}
                    className="flex min-h-10 shrink-0 items-center gap-1.5 rounded-full px-4 text-sm font-bold"
                    style={tab === value ? undefined : { color: "var(--dim)" }}
                  >
                    {t(`tab.${value}`)}
                    {!signedIn && status !== "loading" && value !== "about" ? (
                      <span style={{ opacity: 0.7 }}>
                        <Icon name="lock" size={13} />
                      </span>
                    ) : null}
                  </button>
                ))}
              </div>
              {stuck ? (
                <div className="ms-auto hidden shrink-0 lg:block" data-testid="box-page-bar-action">
                  <BarAction page={page} signedIn={signedIn} member={Boolean(club)} loading={status === "loading" || (signedIn && clubs.isPending)} />
                </div>
              ) : null}
            </div>

            <section id="box-tabpanel" role="tabpanel" aria-labelledby={`box-tab-${tab}`} className="px-4 pb-8 pt-5 lg:px-0 lg:pt-6">
              {tab === "about" ? (
                (sections ?? <AboutBento page={page} onOpenPhoto={setViewer} aside={info} />)
              ) : tab === "club" && club ? (
                // ADR-621: the club brings its own side column (events, channels, members).
                <BoxClubTab club={club} clubs={clubs.data ?? []} onShowEvents={() => select("events")} />
              ) : tab === "schedule" && signedIn ? (
                // ADR-621: the whole width, so desktop shows the week in seven columns.
                <VisitorSchedule page={page} token={tokens!.access_token} member={Boolean(club)} />
              ) : (
                <BoxBento
                  testId="box-tab-bento"
                  aside={info}
                  items={[
                    {
                      key: tab,
                      size: "wide",
                      plain: true,
                      node: (
                        <>
                          {status === "guest" && tab !== "club" ? <LockedTab slug={page.box.slug} tab={tab} /> : null}
                          {/* ADR-621: one «Events» tab; the club's members see the club's events (members-only ones too) and staff create them here. */}
                          {tab === "events" && signedIn ? (club ? <ClubEventsTab club={club} /> : <BoxEvents slug={page.box.slug} token={tokens!.access_token} />) : null}
                          {tab === "posts" && signedIn ? <BoxPosts slug={page.box.slug} token={tokens!.access_token} /> : null}
                        </>
                      ),
                    },
                  ]}
                />
              )}
            </section>
          </>
        )}
      </div>

      {/* Phones: the actions stay in reach above the member tab bar (board 4 Q9). */}
      {/* ADR-621: a member's one action, «Μήνυμα», is in the header, so members get no fixed bar. */}
      {member ? null : (
        <>
      <div aria-hidden="true" className={`${standalone ? "h-24" : "h-36"} lg:hidden`} />
      <div
        className="fixed inset-x-0 z-(--z-sticky) px-4 pt-3 lg:hidden"
        style={{
          bottom: BOTTOM_NAV_SPACE,
          paddingBottom: tabBar ? "0.75rem" : "max(0.75rem, env(safe-area-inset-bottom))",
          background: "color-mix(in srgb, var(--bg) 92%, transparent)",
          borderTop: "1px solid var(--border)",
          backdropFilter: "blur(10px)",
        }}
      >
        <div className="mx-auto max-w-xl">{actions}</div>
      </div>
        </>
      )}

      {viewer !== null && photos.length > 0 ? <PhotoViewer photos={photos} start={viewer} onClose={() => setViewer(null)} /> : null}
      {request ? <SiteRequestSheet slug={page.box.slug} kind={request} privacyHref={`${basePath}/privacy${language === "box" ? "" : `?lang=${encodeURIComponent(language)}`}`} onClose={() => setRequest(null)} /> : null}
    </div>
  );
}

/** «Σχετικά» of a box without a website: one card per part on desktop (ANR 2026-11-09). */
function AboutBento({ page, onOpenPhoto, aside }: { page: PublicBoxPage; onOpenPhoto: (index: number) => void; aside: ReactNode }) {
  const part = (key: AboutPart, size: "wide" | "narrow", desktopHidden = false): BentoItem => ({
    key,
    size,
    desktopHidden,
    node: <AboutTab page={page} onOpenPhoto={onOpenPhoto} parts={[key]} enquiry={false} />,
  });
  return (
    <BoxBento
      aside={aside}
      items={[
        part("intro", "wide"),
        part("photos", "narrow"),
        part("coaches", "narrow"),
        part("clubs", "wide"),
        part("rooms", "wide"),
        part("facts", "narrow"),
        // The info card already shows a single location on desktop.
        part("location", "wide", page.locations.length <= 1),
        // ADR-345 (W2 p6): an enquiry from a visitor without an account becomes a lead.
        { key: "enquiry", size: "narrow", plain: true, node: <EnquiryCard slug={page.box.slug} boxName={page.box.name} /> },
      ]}
    />
  );
}

/** Desktop, top of the right column: the map (opens Google or Apple Maps), the address and the week's hours. */
function InfoCard({
  page,
  apple,
  pinned,
  firstHours,
  onAddress,
}: {
  page: PublicBoxPage;
  apple: boolean;
  pinned: PublicBoxPage["locations"][number] | undefined;
  firstHours: PublicBoxPage["locations"][number] | undefined;
  onAddress: () => void;
}) {
  const t = useTranslations("BoxPage");
  const address = page.locations[0]?.address;
  if (!pinned && !address && !firstHours) return null;
  return (
    <div className="hidden flex-col gap-4 rounded-3xl p-5 lg:flex" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="box-page-info">
      {pinned ? (
        <a
          href={mapsUrl({ latitude: pinned.latitude!, longitude: pinned.longitude! }, page.box.name, apple)}
          target="_blank"
          rel="noreferrer"
          aria-label={t("openInMaps")}
          className="relative block h-44 overflow-hidden rounded-2xl"
          style={{ border: "1px solid var(--border)" }}
        >
          <span aria-hidden="true" className="pointer-events-none block h-full w-full">
            <PlacesMap
              places={[{ id: pinned.id, name: page.box.name, latitude: pinned.latitude!, longitude: pinned.longitude!, selected: true }]}
              ariaLabel={t("mapAria")}
              onBoundsChange={() => undefined}
              onSelect={() => undefined}
            />
          </span>
          <span className="absolute start-2 top-2 rounded-full px-3 py-1 text-xs font-bold" style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" }}>
            {t("openInMaps")}
          </span>
        </a>
      ) : null}
      {address ? (
        <button type="button" onClick={onAddress} className="flex items-start gap-3 text-start text-sm" style={{ color: "var(--text-soft)" }}>
          <Icon name="map-pin" />
          <span>{[address, page.locations[0]!.neighbourhood].filter(Boolean).join(", ")}</span>
        </button>
      ) : null}
      {firstHours ? (
        <div className={address || pinned ? "pt-4" : ""} style={address || pinned ? { borderTop: "1px solid var(--border)" } : undefined}>
          <OpeningHours spans={(firstHours.opening_hours ?? []) as { weekday: number; opens: string; closes: string }[]} />
        </div>
      ) : null}
    </div>
  );
}

/** The sticky bar's one action on desktop: «Γίνε μέλος box»; members have the «Club» tab instead (ADR-621). */
function BarAction({ page, signedIn, member, loading }: { page: PublicBoxPage; signedIn: boolean; member: boolean; loading: boolean }) {
  if (loading || member) return null;
  return <JoinBoxAction page={page} signedIn={signedIn} compact />;
}

function Logo({ page, size = 80, desktopSize, bare = false, className = "" }: { page: PublicBoxPage; size?: number; desktopSize?: number; bare?: boolean; className?: string }) {
  const initials = page.box.name
    .split(/\s+/)
    .slice(0, 2)
    .map((word) => word[0])
    .join("")
    .toUpperCase();
  // Sized through CSS variables so the desktop size can differ (ANR 2026-11-09).
  const style = {
    "--logo-size": `${size}px`,
    "--logo-size-lg": `${desktopSize ?? size}px`,
    border: bare ? "1px solid var(--border)" : "4px solid var(--bg)",
  } as CSSProperties;
  return page.box.logo_url ? (
    // eslint-disable-next-line @next/next/no-img-element -- media from the gym's storage
    <img src={page.box.logo_url} alt="" className={`relative shrink-0 rounded-full object-cover size-(--logo-size) text-[length:calc(var(--logo-size)/2.6)] lg:size-(--logo-size-lg) lg:text-[length:calc(var(--logo-size-lg)/2.6)] ${className}`} style={{ ...style, background: "var(--panel)" }} />
  ) : (
    <span
      aria-hidden="true"
      className={`relative grid shrink-0 place-items-center rounded-full font-extrabold size-(--logo-size) text-[length:calc(var(--logo-size)/2.6)] lg:size-(--logo-size-lg) lg:text-[length:calc(var(--logo-size-lg)/2.6)] ${className}`}
      style={{ ...style, background: "var(--primary)", color: "var(--primary-contrast)" }}
    >
      {initials}
    </span>
  );
}

/**
 * «Γίνε μέλος box» first, then trial and follow (board 4 Q9, board 6 Q1,
 * ANR 2026-11-07). Members have the «Club» tab, so their actions are a
 * labelled «Μήνυμα» and «Κοινοποίηση» (ADR-621).
 * Anyone may write to the box (ADR-282): «Μήνυμα» opens the chat, after
 * signing in when needed.
 */
function Actions({
  page,
  token,
  loading,
  clubId,
  onGuestTrial,
  onShare,
  row = false,
}: {
  page: PublicBoxPage;
  token: string | null;
  loading: boolean;
  clubId: string | null;
  /** ADR-388: a signed-out visitor asks through the website's request form instead of signing in first. */
  onGuestTrial: (() => void) | null;
  /** Members: the header's own share button (the cover's hides on desktop). */
  onShare: () => void;
  /** Desktop header (ANR 2026-11-09): one row beside the box's name. */
  row?: boolean;
}) {
  const signedIn = Boolean(token);
  const t = useTranslations("BoxPage");
  const tSocial = useTranslations("Social");
  const tTrials = useTranslations("Trials");
  if (loading) return <div className={`h-11 animate-pulse rounded-2xl ${row ? "w-96" : ""}`} style={{ background: "var(--panel-raised)" }} />;
  const chat = boxChatHref(page.box.slug);
  const chatHref = signedIn ? chat : `/login?next=${encodeURIComponent(chat)}`;
  const message = (
    <Link
      href={chatHref}
      aria-label={t("messageBox")}
      title={t("messageBox")}
      className="grid min-h-11 min-w-11 shrink-0 place-items-center rounded-2xl"
      style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
      data-testid="box-page-message"
    >
      <Icon name="message-circle" size={18} />
    </Link>
  );
  if (clubId)
    return (
      <div className="flex items-center gap-2">
        <Link
          href={chatHref}
          className="flex min-h-11 items-center gap-2 rounded-2xl px-4 text-sm font-bold"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          data-testid="box-page-message"
        >
          <Icon name="message-circle" size={18} />
          {t("message")}
        </Link>
        <button
          type="button"
          onClick={onShare}
          aria-label={t("share")}
          title={t("share")}
          className="hidden min-h-11 min-w-11 place-items-center rounded-2xl lg:grid"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          data-testid="box-page-header-share"
        >
          <Icon name="share" size={18} />
        </button>
      </div>
    );
  return (
    <div className={row ? "flex items-start gap-2" : "flex flex-col gap-2"}>
      <JoinBoxAction page={page} signedIn={signedIn} compact={row} />
      <div className={`flex items-start gap-2 ${row ? "w-80" : ""}`}>
        {!signedIn && onGuestTrial ? (
          <button
            type="button"
            onClick={onGuestTrial}
            className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-3 text-sm font-bold"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            data-testid="box-page-site-trial"
          >
            {tTrials("ask")}
          </button>
        ) : (
          <TrialButton page={page} token={token} />
        )}
        <div className="min-w-0 flex-1">
          {signedIn ? (
            <FollowButton targetType="organization" targetId={page.box.organization_id} wide quiet />
          ) : (
            <Link
              href={`/login?next=${encodeURIComponent(`/b/${page.box.slug}`)}`}
              className="flex min-h-11 w-full items-center justify-center rounded-2xl text-sm font-bold"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {tSocial("follow")}
            </Link>
          )}
        </div>
        {message}
      </div>
    </div>
  );
}

/**
 * The box's own domain (ANR s3 A): «Κλείσε δοκιμαστικό» is the page's one
 * filled button; the message icon opens «Ρώτησε κάτι». Both open the request
 * sheet: a request becomes a lead, never a booking.
 */
function SiteActions({ site, onRequest }: { site: PublicSite; onRequest: (kind: "trial" | "contact") => void }) {
  const t = useTranslations("BoxSite");
  return (
    <div className="flex items-start gap-2">
      {site.forms.trial ? (
        <button
          type="button"
          onClick={() => onRequest("trial")}
          className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-3 text-sm font-bold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          data-testid="site-book-trial"
        >
          {t("bookTrial")}
        </button>
      ) : null}
      {site.forms.contact ? (
        <button
          type="button"
          onClick={() => onRequest("contact")}
          aria-label={t("askSomething")}
          title={t("askSomething")}
          className={`grid min-h-11 min-w-11 place-items-center rounded-2xl ${site.forms.trial ? "shrink-0" : "flex-1"}`}
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          data-testid="site-ask"
        >
          <Icon name="message-circle" size={18} />
        </button>
      ) : null}
    </div>
  );
}
