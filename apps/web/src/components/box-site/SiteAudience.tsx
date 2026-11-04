"use client";

import type { ReactNode } from "react";

import { useSession } from "@/components/session-provider";

/**
 * ADR-530: guests (and the server's HTML) get the box's website; a signed-in
 * member keeps the app's box page. The swap happens only once the session
 * is known to be signed in, so a guest never sees the app view flash.
 */
export function SiteAudience({ website, app }: { website: ReactNode; app: ReactNode }) {
  const { status } = useSession();
  return <>{status === "authenticated" ? app : website}</>;
}
