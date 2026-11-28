"use client";

import { useEffect, useRef, useState, type KeyboardEvent, type MouseEvent } from "react";
import Link from "next/link";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchPerson, fetchPersonMedia, personKey } from "@/api/social";
import { useSession } from "@/components/session-provider";
import { personMediaKey, tileLabel } from "@/components/social/MediaGrid";
import { mediaTile } from "@/components/social/social-model";
import { LockIcon } from "@/components/ui/LockIcon";
import { Layer } from "@/components/ui/Layer";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

/** How many of the newest media the viewer shows under the photo (mockup C). */
export const AVATAR_VIEWER_STRIP = 4;

/** A person's profile path; your own is Εγώ. */
export function profileHref(personId: string, mine: boolean, query = "") {
  return `${mine ? "/me" : `/people/${personId}`}${query}`;
}

/**
 * Whether the viewer locks «Πολυμέσα»: a private account you do not follow
 * (ANR 2026-11-28, pick 4). A public account shows whatever the API lets
 * you see, by the posts' own audience.
 */
export function avatarMediaLocked(person: { is_me?: boolean; private?: boolean; my_status?: string | null } | undefined) {
  if (!person || person.is_me) return false;
  return Boolean(person.private) && person.my_status !== "active";
}

/**
 * A person's photo that opens full size on a press (ANR 2026-11-28, mockup C).
 *
 * Most photos sit inside a row or card that links to the profile. There the
 * press on the photo is the photo's own, and the name and the rest of the
 * card still go to the profile, as before. To keep the page valid (no control
 * inside a link) and the link's name unchanged, a nested photo stays a plain
 * element that answers the pointer; keyboard and screen-reader users follow
 * the row's link and open the photo from the profile's header. Standing on its
 * own, the photo is a real button.
 */
export function AvatarButton({
  personId,
  name,
  url,
  onProfile = false,
  className,
  style,
  children,
}: {
  personId: string;
  name: string;
  url: string;
  /** Already on this person's profile: the viewer offers only «Πολυμέσα». */
  onProfile?: boolean;
  className?: string;
  style?: React.CSSProperties;
  children: React.ReactNode;
}) {
  const t = useTranslations("Social");
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLSpanElement>(null);
  // Known only once mounted, so the server and the first render agree.
  const [standalone, setStandalone] = useState(false);
  useEffect(() => {
    setStandalone(!ref.current?.parentElement?.closest(INTERACTIVE_ANCESTOR));
  }, []);
  const openViewer = (event: MouseEvent | KeyboardEvent) => {
    // The row around the photo may be a link to the profile: this press is the photo's.
    event.preventDefault();
    event.stopPropagation();
    setOpen(true);
  };
  return (
    <>
      <span
        ref={ref}
        {...(standalone
          ? {
              role: "button",
              tabIndex: 0,
              "aria-label": t("avatarView", { name }),
              "aria-haspopup": "dialog" as const,
              onKeyDown: (event: KeyboardEvent) => {
                if (event.key === "Enter" || event.key === " ") openViewer(event);
              },
            }
          : {})}
        data-testid="avatar-button"
        className={`block shrink-0 cursor-zoom-in rounded-full ${className ?? ""}`}
        style={style}
        onClick={openViewer}
      >
        {children}
      </span>
      {open ? <AvatarViewer personId={personId} name={name} url={url} onProfile={onProfile} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

/** What already takes the press around a photo (a link, a button, a whole-row control). */
const INTERACTIVE_ANCESTOR = "a[href], button, [role='button'], [role='link'], label, summary";

/**
 * The photo full size on a dark screen (mockup C): name on top, the four
 * newest media under it, «Προφίλ» and «Όλα τα πολυμέσα» at the bottom. On
 * your own photo «Αλλαγή φωτογραφίας» joins them. Closes with ✕, Escape or a
 * swipe down.
 */
export function AvatarViewer({
  personId,
  name,
  url,
  onProfile = false,
  onClose,
}: {
  personId: string;
  name: string;
  url: string;
  onProfile?: boolean;
  onClose: () => void;
}) {
  const t = useTranslations("Social");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const dialog = useModalFocusTrap<HTMLDivElement>(onClose);
  const touch = useRef<{ x: number; y: number } | null>(null);
  const person = useQuery({ queryKey: personKey(personId), enabled: Boolean(token), queryFn: () => fetchPerson(token!, personId) });
  const locked = avatarMediaLocked(person.data);
  const media = useInfiniteQuery({
    queryKey: personMediaKey(personId),
    enabled: Boolean(token) && person.isSuccess && !locked,
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchPersonMedia(token!, personId, pageParam),
    getNextPageParam: (page) => page.next_cursor ?? null,
  });
  const mine = Boolean(person.data?.is_me);
  const tiles = (media.data?.pages[0]?.posts ?? [])
    .map((post) => ({ id: post.id, tile: mediaTile(post) }))
    .filter((entry) => entry.tile !== null)
    .slice(0, AVATAR_VIEWER_STRIP);
  const mediaHref = (post?: string) => profileHref(personId, mine, `?tab=media${post ? `&post=${encodeURIComponent(post)}` : ""}`);
  const handle = person.data?.handle;
  const control = "flex min-h-12 items-center justify-center gap-2 rounded-2xl px-3 text-sm font-bold";

  return (
    <Layer>
      <div
        ref={dialog}
        role="dialog"
        aria-modal="true"
        aria-label={t("avatarViewerTitle", { name })}
        tabIndex={-1}
        data-testid="avatar-viewer"
        className="fixed inset-0 z-(--z-fullscreen) flex flex-col outline-none"
        style={{ background: "var(--scrim-strong)", color: "var(--on-media)" }}
        // The viewer is portalled, but React still bubbles its presses to the
        // row that opened it, which may be a link to the profile.
        onClick={(event) => event.stopPropagation()}
        onTouchStart={(event) => {
          touch.current = { x: event.touches[0].clientX, y: event.touches[0].clientY };
        }}
        onTouchEnd={(event) => {
          if (!touch.current) return;
          const dx = event.changedTouches[0].clientX - touch.current.x;
          const dy = event.changedTouches[0].clientY - touch.current.y;
          touch.current = null;
          if (dy > 90 && Math.abs(dy) > Math.abs(dx)) onClose();
        }}
      >
        <header className="mx-auto flex w-full max-w-xl items-center gap-3 px-4 pt-[max(0.75rem,env(safe-area-inset-top))]">
          <p className="min-w-0 grow">
            <span className="block truncate font-extrabold">{name}</span>
            {handle ? <span className="block truncate text-xs opacity-75">@{handle}</span> : null}
          </p>
          <button
            type="button"
            data-dialog-close
            onClick={onClose}
            aria-label={t("avatarViewerClose")}
            className="grid h-11 w-11 shrink-0 place-items-center rounded-full"
            style={{ background: "var(--media-control-inverse)" }}
          >
            <svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round">
              <path d="M6 6l12 12M18 6 6 18" />
            </svg>
          </button>
        </header>

        <div className="flex min-h-0 flex-1 items-center justify-center p-4">
          {/* eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin */}
          <img
            src={url}
            alt={t("avatarViewerTitle", { name })}
            data-testid="avatar-viewer-photo"
            className="aspect-square max-h-full w-full max-w-xl rounded-md object-cover"
          />
        </div>

        <footer className="mx-auto flex w-full max-w-xl flex-col gap-2 px-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
          {locked ? (
            <p className="text-sm opacity-85" data-testid="avatar-viewer-locked">{t("avatarViewerLocked")}</p>
          ) : tiles.length > 0 ? (
            <ul className="grid grid-cols-4 gap-1" data-testid="avatar-viewer-strip">
              {tiles.map(({ id, tile }) => (
                <li key={id}>
                  <Link
                    href={mediaHref(id)}
                    onClick={onClose}
                    aria-label={tileLabel(tile!, t)}
                    className="relative block aspect-square overflow-hidden rounded-lg"
                    style={{ background: "var(--media-control-inverse)" }}
                  >
                    {tile!.src ? (
                      // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
                      <img src={tile!.src} alt="" loading="lazy" decoding="async" className="absolute inset-0 h-full w-full object-cover" />
                    ) : null}
                    {tile!.kind === "video" ? (
                      <svg aria-hidden="true" className="absolute bottom-1 end-1" width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
                        <path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.5-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5Z" />
                      </svg>
                    ) : null}
                  </Link>
                </li>
              ))}
            </ul>
          ) : null}

          <div className={`grid gap-2 ${onProfile ? "grid-cols-1" : "grid-cols-2"}`}>
            {onProfile ? null : (
              <Link href={profileHref(personId, mine)} onClick={onClose} className={control} style={{ background: "var(--media-control-inverse)" }}>
                {t("avatarViewerProfile")}
              </Link>
            )}
            {locked ? (
              <button type="button" disabled className={`${control} opacity-60`} style={{ background: "var(--media-control-inverse)" }}>
                <LockIcon />
                {t("avatarViewerMedia")}
              </button>
            ) : (
              <Link
                href={mediaHref()}
                onClick={onClose}
                className={control}
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              >
                {t(tiles.length > 0 ? "avatarViewerAllMedia" : "avatarViewerMedia")}
              </Link>
            )}
          </div>
          {mine ? (
            <Link href="/me/settings#avatar" onClick={onClose} className={control} style={{ border: "1px solid var(--media-control-inverse)" }}>
              {t("avatarViewerChange")}
            </Link>
          ) : null}
        </footer>
      </div>
    </Layer>
  );
}
