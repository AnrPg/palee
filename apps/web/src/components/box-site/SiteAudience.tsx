"use client";

import { useSyncExternalStore, type ReactNode } from "react";

import { useSession } from "@/components/session-provider";

const subscribeNever = () => () => undefined;
// ADR-641: «Ιστοσελίδα» on the box page opens `/b/<slug>?site=1`, the website even for a signed-in member.
const readWantsSite = () => new URLSearchParams(window.location.search).get("site") === "1";
const serverWantsSite = () => false;

/**
 * ADR-530: guests (and the server's HTML) get the box's website; a signed-in
 * member keeps the app's box page, unless they asked for the website
 * (`?site=1`). The swap happens only once the session is known to be signed
 * in, so a guest never sees the app view flash.
 */
export function SiteAudience({ website, app }: { website: ReactNode; app: ReactNode }) {
  const { status } = useSession();
  const wantsSite = useSyncExternalStore(subscribeNever, readWantsSite, serverWantsSite);
  return <>{status === "authenticated" && !wantsSite ? app : website}</>;
}
