"use client";


import {useUiTranslations} from "@/i18n/ui";
import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";

import { PaleeMark } from "@/components/branding/PaleeMark";
import { PaleeTagline } from "@/components/branding/PaleeTagline";
import { useSession } from "@/components/session-provider";
import { membershipWorkspaceHref } from "@/lib/organization-slug";
import { useSelectedMembershipRole } from "@/lib/membership-role";

type AuthGuardProps = {
  children: React.ReactNode;
  roles?: Array<"member" | "athlete" | "admin">;
  roleRedirects?: Partial<Record<"member" | "athlete" | "admin", string>>;
};

type AllowedRole = NonNullable<AuthGuardProps["roles"]>[number];
type SelectedMembership = ReturnType<typeof useSelectedMembershipRole>["membership"];
type RedirectRole = "member" | "athlete" | "admin";

function isAllowedRole(value: string): value is AllowedRole {
  return value === "member" || value === "athlete" || value === "admin";
}

export function resolveRoleRedirect(
  configuredRedirect: string | undefined,
  membership: SelectedMembership,
) {
  return configuredRedirect === "/admin" && membership
    ? membershipWorkspaceHref(membership)
    : configuredRedirect;
}

// Vendors (SaaS operators, `currentUser.vendor`) are exempt from
// roleRedirects: their tenant-membership role (if any) is irrelevant to
// where they land, since the platform console is their home regardless.
export function AuthGuard({ children, roles, roleRedirects }: AuthGuardProps) {
  const i18n = useUiTranslations();
  const router = useRouter();
  const pathname = usePathname();
  const { status, currentUser, restoreFailed } = useSession();
  const { isLoading: membershipRoleLoading, membership, role } = useSelectedMembershipRole();
  const accountRole = currentUser?.role;
  const redirectRole =
    membership || !isAllowedRole(accountRole ?? "") ? role : (accountRole as RedirectRole);
  const awaitingTenantAdminMembership =
    status === "authenticated" &&
    !currentUser?.vendor &&
    accountRole === "admin" &&
    roleRedirects?.admin === "/admin" &&
    !membership;

  useEffect(() => {
    if (status === "guest") {
      // Keep the query string and fragment so links such as a company
      // enrollment link (ADR-098) or an emailed activation link (ADR-205)
      // survive signing in.
      // A restore that failed or timed out says so on the sign-in form.
      router.replace(
        `/login?next=${encodeURIComponent(pathname + window.location.search + window.location.hash)}${
          restoreFailed ? "&restore=failed" : ""
        }`,
      );
      return;
    }

    if (status === "authenticated" && currentUser && !membershipRoleLoading) {
      if (!currentUser.vendor) {
        const roleKey = redirectRole;
        const configuredRedirect = roleRedirects?.[roleKey];
        const redirect = resolveRoleRedirect(configuredRedirect, membership);
        if (redirect) {
          router.replace(redirect);
          return;
        }
      }
      if (roles && (!isAllowedRole(redirectRole) || !roles.includes(redirectRole))) {
        router.replace("/");
      }
    }
  }, [
    currentUser,
    membership,
    membershipRoleLoading,
    pathname,
    redirectRole,
    restoreFailed,
    roles,
    roleRedirects,
    router,
    status,
  ]);

  if (
    status === "loading" ||
    (status === "authenticated" && roles && membershipRoleLoading) ||
    awaitingTenantAdminMembership
  ) {
    return (
      <main className="flex min-h-screen flex-col items-center justify-center gap-5 bg-[var(--bg)] px-6 text-center">
        <PaleeMark className="size-14" />
        {/* ANR 2026-11-08: the tagline greets every app start. */}
        <PaleeTagline className="max-w-xs text-lg text-[var(--text)]" />
        <p className="text-sm font-medium uppercase tracking-[0.24em] text-[var(--dim)]">
          {i18n("restoringSession5a59aa5")}
        </p>
        <SplashFallback
          message={i18n("restoreTakingLong")}
          retryLabel={i18n("restoreTryAgain")}
          retryHref={pathname}
          loginLabel={i18n("restoreSignInAgain")}
        />
      </main>
    );
  }

  if (status === "guest") return null;

  if (roles && currentUser && (!isAllowedRole(redirectRole) || !roles.includes(redirectRole))) {
    return null;
  }

  const roleKey = currentUser && !currentUser.vendor ? redirectRole : undefined;
  if (roleKey && roleRedirects?.[roleKey]) return null;

  return <>{children}</>;
}

/**
 * Shown by CSS alone (globals.css `.splash-fallback`) once the splash has
 * stayed up too long, so it appears even when the page's JavaScript never
 * ran (an old browser, a failed download): plain links, no handlers.
 */
function SplashFallback({
  message,
  retryLabel,
  retryHref,
  loginLabel,
}: {
  message: string;
  retryLabel: string;
  retryHref: string;
  loginLabel: string;
}) {
  return (
    <div className="splash-fallback flex max-w-xs flex-col items-center gap-3" data-testid="splash-fallback">
      <p className="text-sm text-[var(--text-soft)]">{message}</p>
      <div className="flex flex-wrap justify-center gap-2">
        <a
          href={retryHref}
          className="rounded-2xl px-4 py-2 text-sm font-semibold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {retryLabel}
        </a>
        <a
          href={`/login?next=${encodeURIComponent(retryHref)}&restore=failed`}
          className="rounded-2xl border px-4 py-2 text-sm font-semibold"
          style={{ borderColor: "var(--border-strong)", color: "var(--text-soft)" }}
        >
          {loginLabel}
        </a>
      </div>
    </div>
  );
}
