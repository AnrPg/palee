"use client";

import { useSession } from "@/components/session-provider";
import { PersonProfile } from "@/components/social/PersonProfile";
import { PaleeTagline } from "@/components/branding/PaleeTagline";

/** Εγώ (ADR-554): your own profile, the very page others see, with the ☰ «Μόνο για σένα». */
export function MyProfile() {
  const { currentUser } = useSession();
  if (!currentUser) return null;
  return (
    <>
      <PersonProfile id={currentUser.id} />
      {/* ANR 2026-11-08: the tagline, quietly, at the very end of Εγώ. */}
      <footer className="mx-auto w-full max-w-xl px-4 pb-8 text-center">
        <PaleeTagline className="text-sm text-[var(--muted)]" />
      </footer>
    </>
  );
}
