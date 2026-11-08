"use client";

import { useSession } from "@/components/session-provider";
import { PersonProfile } from "@/components/social/PersonProfile";

/** Εγώ (ADR-554): your own profile, the very page others see, with the ☰ «Μόνο για σένα». */
export function MyProfile() {
  const { currentUser } = useSession();
  if (!currentUser) return null;
  return <PersonProfile id={currentUser.id} />;
}
