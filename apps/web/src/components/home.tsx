"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect } from "react";

import { useSession } from "@/components/session-provider";
import { HomeHub } from "@/components/member-app/HomeHub";
import { PlatformOrganizationsPage } from "@/components/platform/PlatformOrganizationsPage";
import { appOpenLanding, claimAppOpenLanding, noteRoute } from "@/lib/app-open-landing";
import { needsFirstRun } from "@/lib/first-run";
import { useSelectedMembershipRole } from "@/lib/membership-role";

// Vendors (SaaS operators) have no tenant homepage to speak of by default -
// the platform console *is* their home. "/platform/organizations" stays
// live as an alias (bookmarks, the TopNav dropdown link) pointing at the
// same component.
//
// A vendor who also holds a real membership somewhere can still choose to
// view that org as that role: navigating under /org/:slug (via the "Your
// memberships" links on the platform page, or the TopNav dropdown) always
// renders the ordinary tenant workspace, vendor status notwithstanding -
// only the bare "/" defaults to the platform console.
//
// Everyone else reaching "/" is a member or athlete (admins are redirected to
// /admin by the route), so "/" is the Αρχική hub (ADR-137). W7 screen 12:
// a member of exactly one box opens the app on Box instead; tapping Feed
// afterwards shows Feed.
export function Home() {
  const pathname = usePathname();
  const router = useRouter();
  const { currentUser } = useSession();
  const inOrganizationContext = pathname.startsWith("/org/");
  // ADR-183: a new account's first stop is the first-run, once.
  const firstRun = needsFirstRun(currentUser);
  const { memberships, isLoading } = useSelectedMembershipRole();
  const vendor = Boolean(currentUser?.vendor);

  useEffect(() => {
    if (firstRun) router.replace("/welcome");
  }, [firstRun, router]);

  useEffect(() => {
    noteRoute(pathname);
    if (firstRun || !currentUser || isLoading || inOrganizationContext || pathname !== "/") return;
    if (!claimAppOpenLanding(pathname)) return;
    const landing = appOpenLanding({ membershipCount: memberships.length, vendor });
    if (landing) router.replace(landing);
  }, [firstRun, currentUser, isLoading, inOrganizationContext, pathname, memberships.length, vendor, router]);

  if (firstRun) return null;
  if (currentUser?.vendor && !inOrganizationContext) return <PlatformOrganizationsPage />;

  return <HomeHub />;
}
