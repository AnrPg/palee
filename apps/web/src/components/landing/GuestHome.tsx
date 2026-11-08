"use client";

import { useState, type ReactNode } from "react";

import { useSession } from "@/components/session-provider";
import { GuestLanding } from "@/components/landing/GuestLanding";

/**
 * palee.app/ (ADR-555): guests see the landing, everyone else the app. Once a
 * guest opens the form the landing stays until the form is done, so a new
 * account still gets its recovery codes before the app takes over.
 */
export function GuestHome({ children }: { children: ReactNode }) {
  const { status } = useSession();
  const [holding, setHolding] = useState(false);
  if (status === "guest" || holding) {
    return <GuestLanding onAuthOpen={() => setHolding(true)} onAuthDone={() => setHolding(false)} />;
  }
  return <>{children}</>;
}
