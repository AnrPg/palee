"use client";

import { useRouter } from "next/navigation";
import { useSyncExternalStore, type MouseEvent, type ReactNode } from "react";

import { useSession } from "@/components/session-provider";

// Back and forward between the website and the app's page change the address without a new mount.
const subscribeHistory = (onChange: () => void) => {
  window.addEventListener("popstate", onChange);
  return () => window.removeEventListener("popstate", onChange);
};
// ADR-641: «Ιστοσελίδα» on the box page opens `/b/<slug>?site=1`, the website even for a signed-in member.
const readWantsSite = () => new URLSearchParams(window.location.search).get("site") === "1";
const serverWantsSite = () => false;

/** `/b/<slug>` of the address, the root every page of this website lives under. */
function siteRoot(pathname: string) {
  const match = pathname.match(/^\/b\/[^/]+/);
  return match ? match[0] : null;
}

/**
 * ADR-530: guests (and the server's HTML) get the box's website; a signed-in
 * member keeps the app's box page, unless they asked for the website
 * (`?site=1`). The swap happens only once the session is known to be signed
 * in, so a guest never sees the app view flash.
 *
 * ADR-641: while a signed-in member reads the website, its own links
 * («Πρόγραμμα», «Πακέτα», «Coaches», languages) keep `?site=1`, so they stay
 * on the website instead of falling back to the app's box page.
 */
export function SiteAudience({ website, app }: { website: ReactNode; app: ReactNode }) {
  const { status } = useSession();
  const router = useRouter();
  const wantsSite = useSyncExternalStore(subscribeHistory, readWantsSite, serverWantsSite);
  const signedIn = status === "authenticated";
  if (signedIn && !wantsSite) return <>{app}</>;
  if (!signedIn) return <>{website}</>;

  function keepWebsite(event: MouseEvent<HTMLDivElement>) {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const anchor = (event.target as Element).closest?.("a[href]");
    if (!(anchor instanceof HTMLAnchorElement) || (anchor.target && anchor.target !== "_self")) return;
    const url = new URL(anchor.href, window.location.href);
    const root = siteRoot(window.location.pathname);
    if (url.origin !== window.location.origin || !root || (url.pathname !== root && !url.pathname.startsWith(`${root}/`))) return;
    if (url.searchParams.get("site") === "1") return;
    url.searchParams.set("site", "1");
    event.preventDefault();
    event.stopPropagation();
    router.push(url.pathname + url.search + url.hash);
  }

  return (
    <div className="contents" onClickCapture={keepWebsite}>
      {website}
    </div>
  );
}
