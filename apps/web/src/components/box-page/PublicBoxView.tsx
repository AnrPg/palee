"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useRef, useState, useSyncExternalStore } from "react";
import { useTranslations } from "next-intl";

import type { PublicSite } from "@/api/box-site";
import type { PublicBoxPage } from "@/api/social";
import { SiteConsentProvider } from "@/components/box-site/SiteConsent";
import { SiteLanguageSwitch } from "@/components/box-site/SiteLanguageSwitch";
import { SiteProgrammesNavLink } from "@/components/box-site/SiteProgrammes";
import { SiteRequestSheet } from "@/components/box-site/SiteRequestSheet";
import { SiteSections } from "@/components/box-site/SiteSections";
import { useMyClubs } from "@/components/community/use-community";
import { BOTTOM_NAV_SPACE, useBottomTabBarVisible } from "@/components/nav/BottomNav";
import { useSession } from "@/components/session-provider";
import { FollowButton } from "@/components/social/FollowButton";
import { TrialButton } from "@/components/trials/TrialButton";
import { mapsUrl, readApple, serverApple, subscribeNever } from "@/lib/maps";
import { siteBasePath, type SiteLanguage } from "@/lib/public-site";

import { AboutTab, OpeningHours } from "./AboutTab";
import { BoxEvents } from "./BoxEvents";
import { BoxPosts } from "./BoxPosts";
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

const TABS = ["about", "schedule", "events", "posts"] as const;
type Tab = (typeof TABS)[number];

// The open tab lives in the URL hash (#schedule) so a shared link and the
// way back from sign-in land on it.
function subscribeHash(onChange: () => void) {
  window.addEventListener("hashchange", onChange);
  return () => window.removeEventListener("hashchange", onChange);
}
const readHash = () => window.location.hash.slice(1);
const serverHash = () => "";

/**
 * The public box page (ADR-142; plan §5a board 4, board 5 Q1–Q2). Phones:
 * cover, logo and name, sticky tabs, and a fixed bottom bar with the actions.
 * Desktop (board 5 Q1): a full-width cover, content capped at 1200 px, and a
 * sticky card on the right with the actions, the map, the address and the
 * week's hours; the map opens in Google or Apple Maps.
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
  const tab: Tab = TABS.includes(hash as Tab) ? (hash as Tab) : "about";
  const tabsRef = useRef<HTMLDivElement>(null);
  const [viewer, setViewer] = useState<number | null>(null);
  const [copied, setCopied] = useState(false);
  const [request, setRequest] = useState<"trial" | "contact" | null>(null);
  const basePath = siteBasePath(page.box.slug, standalone);

  const signedIn = status === "authenticated" && Boolean(tokens?.access_token);
  const club = clubs.data?.find((entry) => entry.kind === "gym" && entry.organization_id === page.box.organization_id) ?? null;
  const photos = [...(page.profile.cover ? [page.profile.cover] : []), ...page.profile.photos];
  const place = page.locations.find((location) => location.neighbourhood || location.city);
  const line = place?.neighbourhood ?? place?.city ?? null;
  const firstHours = page.locations.find((location) => (location.opening_hours ?? []).length > 0);
  const apple = useSyncExternalStore(subscribeNever, readApple, serverApple);
  const pinned = page.locations.find((location) => location.latitude != null && location.longitude != null);

  function select(next: Tab) {
    window.history.replaceState(null, "", next === "about" ? window.location.pathname : `#${next}`);
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
    />
  );
  const sections = site ? (
    <SiteSections page={page} site={site} language={language} basePath={basePath} onOpenPhoto={setViewer} onRequest={setRequest} />
  ) : null;
  const roundButtonClass = "grid h-10 w-10 place-items-center rounded-full";

  return (
    <div className="w-full">
      <header className="relative">
        <div
          className="relative h-52 w-full overflow-hidden sm:h-64 lg:h-96"
          style={{ background: "linear-gradient(135deg, var(--deep), var(--primary))" }}
        >
          {page.profile.cover ? (
            <button type="button" onClick={() => setViewer(0)} aria-label={t("openPhotos")} className="block h-full w-full">
              {/* eslint-disable-next-line @next/next/no-img-element -- media from the gym's storage */}
              <img src={page.profile.cover.url} alt="" className="h-full w-full object-cover" />
            </button>
          ) : null}
          <div className="absolute inset-x-0 top-0 mx-auto flex max-w-[75rem] justify-between p-3 pt-[max(0.75rem,env(safe-area-inset-top))] lg:px-6 lg:pt-6">
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
              <button type="button" onClick={() => void share()} aria-label={t("share")} className={roundButtonClass} style={{ background: "var(--media-control)", color: "var(--on-media)" }}>
                <Icon name={copied ? "check" : "share"} />
              </button>
            </span>
          </div>
        </div>
        <span role="status" className="sr-only">{copied ? t("linkCopied") : ""}</span>
        <div className="mx-auto flex max-w-[75rem] flex-col gap-1 px-4 lg:flex-row lg:items-end lg:gap-5 lg:px-6">
          <Logo page={page} className="-mt-10 lg:-mt-14" size={80} />
          <div className="min-w-0 lg:pb-1">
            <h1 className="mt-2 text-2xl font-extrabold lg:text-3xl" style={{ color: "var(--text)" }}>{page.box.name}</h1>
            {line ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{line}</p> : null}
          </div>
          {standalone || tab === "about" ? (
            <div className="lg:ms-auto lg:pb-1">
              <SiteProgrammesNavLink site={site} />
            </div>
          ) : null}
        </div>
      </header>

      {!standalone && signedIn && !club && !clubs.isPending ? (
        <div className="mx-auto max-w-[75rem] lg:mt-6 lg:px-6">
          <GuestBanner token={tokens!.access_token} box={page.box} />
        </div>
      ) : null}

      <div className="mx-auto max-w-[75rem] lg:mt-8 lg:grid lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start lg:gap-10 lg:px-6">
        <main className="min-w-0">
          {standalone ? (
            <section className="px-4 pb-8 pt-5 lg:px-0">{sections}</section>
          ) : (
          <>
          <div
            ref={tabsRef}
            role="tablist"
            aria-label={t("tabsAria")}
            className="sticky top-(--top-bar-space) z-(--z-sticky) mt-4 flex gap-1 transition-[top] duration-300 motion-reduce:transition-none overflow-x-auto px-4 pb-2 pt-[max(0.5rem,env(safe-area-inset-top))] lg:mt-0 lg:px-0"
            style={{ background: "var(--bg)", borderBottom: "1px solid var(--border)" }}
          >
            {TABS.map((value) => (
              <button
                key={value}
                type="button"
                role="tab"
                id={`box-tab-${value}`}
                aria-selected={tab === value}
                aria-controls="box-tabpanel"
                onClick={() => select(value)}
                className="relative flex min-h-11 shrink-0 items-center gap-1.5 px-3 text-sm font-bold"
                style={{ color: tab === value ? "var(--text)" : "var(--dim)" }}
              >
                {t(`tab.${value}`)}
                {!signedIn && status !== "loading" && value !== "about" ? (
                  <span style={{ opacity: 0.7 }}>
                    <Icon name="lock" size={13} />
                  </span>
                ) : null}
                {tab === value ? <span aria-hidden="true" className="absolute inset-x-2 -bottom-2 h-0.5 rounded-full" style={{ background: "var(--primary)" }} /> : null}
              </button>
            ))}
          </div>

          <section id="box-tabpanel" role="tabpanel" aria-labelledby={`box-tab-${tab}`} className="px-4 pb-8 pt-5 lg:px-0">
            {tab === "about" ? sections ?? <AboutTab page={page} onOpenPhoto={setViewer} /> : null}
            {tab !== "about" && status === "guest" ? <LockedTab slug={page.box.slug} tab={tab} /> : null}
            {tab === "schedule" && signedIn ? <VisitorSchedule page={page} token={tokens!.access_token} member={Boolean(club)} /> : null}
            {tab === "events" && signedIn ? <BoxEvents slug={page.box.slug} token={tokens!.access_token} /> : null}
            {tab === "posts" && signedIn ? <BoxPosts slug={page.box.slug} token={tokens!.access_token} /> : null}
          </section>
          </>
          )}
        </main>

        <aside className="hidden lg:sticky lg:top-6 lg:block">
          <div className="flex flex-col gap-4 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            {actions}
            {pinned ? (
              <a
                href={mapsUrl({ latitude: pinned.latitude!, longitude: pinned.longitude! }, page.box.name, apple)}
                target="_blank"
                rel="noreferrer"
                aria-label={t("openInMaps")}
                className="relative block h-40 overflow-hidden rounded-2xl"
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
                <span
                  className="absolute start-2 top-2 rounded-full px-3 py-1 text-xs font-bold"
                  style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" }}
                >
                  {t("openInMaps")}
                </span>
              </a>
            ) : null}
            {page.locations[0]?.address ? (
              <button type="button" onClick={() => select("about")} className="flex items-start gap-3 text-start text-sm" style={{ color: "var(--text-soft)" }}>
                <Icon name="map-pin" />
                <span>{[page.locations[0].address, page.locations[0].neighbourhood].filter(Boolean).join(", ")}</span>
              </button>
            ) : null}
            {firstHours ? (
              <div className="pt-4" style={{ borderTop: "1px solid var(--border)" }}>
                <OpeningHours spans={(firstHours.opening_hours ?? []) as { weekday: number; opens: string; closes: string }[]} />
              </div>
            ) : null}
          </div>
        </aside>
      </div>

      {/* Phones: the actions stay in reach above the member tab bar (board 4 Q9). */}
      <div aria-hidden="true" className={`${club || standalone ? "h-24" : "h-36"} lg:hidden`} />
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

      {viewer !== null && photos.length > 0 ? <PhotoViewer photos={photos} start={viewer} onClose={() => setViewer(null)} /> : null}
      {request ? <SiteRequestSheet slug={page.box.slug} kind={request} privacyHref={`${basePath}/privacy${language === "box" ? "" : `?lang=${encodeURIComponent(language)}`}`} onClose={() => setRequest(null)} /> : null}
    </div>
  );
}

function Logo({ page, size = 80, className = "" }: { page: PublicBoxPage; size?: number; className?: string }) {
  const initials = page.box.name
    .split(/\s+/)
    .slice(0, 2)
    .map((word) => word[0])
    .join("")
    .toUpperCase();
  const style = { width: size, height: size, border: "4px solid var(--bg)" };
  return page.box.logo_url ? (
    // eslint-disable-next-line @next/next/no-img-element -- media from the gym's storage
    <img src={page.box.logo_url} alt="" className={`relative shrink-0 rounded-full object-cover ${className}`} style={{ ...style, background: "var(--panel)" }} />
  ) : (
    <span
      aria-hidden="true"
      className={`relative grid shrink-0 place-items-center rounded-full font-extrabold ${className}`}
      style={{ ...style, background: "var(--primary)", color: "var(--primary-contrast)", fontSize: size / 2.6 }}
    >
      {initials}
    </span>
  );
}

/**
 * «Γίνε μέλος box» first, then trial and follow (board 4 Q9, board 6 Q1,
 * ANR 2026-11-07); members open their club instead.
 * Anyone may write to the box (ADR-282): «Μήνυμα» opens the chat, after
 * signing in when needed.
 */
function Actions({
  page,
  token,
  loading,
  clubId,
  onGuestTrial,
}: {
  page: PublicBoxPage;
  token: string | null;
  loading: boolean;
  clubId: string | null;
  /** ADR-388: a signed-out visitor asks through the website's request form instead of signing in first. */
  onGuestTrial: (() => void) | null;
}) {
  const signedIn = Boolean(token);
  const t = useTranslations("BoxPage");
  const tSocial = useTranslations("Social");
  const tTrials = useTranslations("Trials");
  if (loading) return <div className="h-11 animate-pulse rounded-2xl" style={{ background: "var(--panel-raised)" }} />;
  const chat = boxChatHref(page.box.slug);
  const message = (
    <Link
      href={signedIn ? chat : `/login?next=${encodeURIComponent(chat)}`}
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
      <div className="flex items-start gap-2">
        <Link href={`/clubs/${clubId}`} className="flex min-h-11 flex-1 items-center justify-center gap-2 rounded-2xl text-sm font-bold" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}>
          <Icon name="check" size={16} />
          {t("memberOpenClub")}
        </Link>
        {message}
      </div>
    );
  return (
    <div className="flex flex-col gap-2">
      <JoinBoxAction page={page} signedIn={signedIn} />
      <div className="flex items-start gap-2">
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
