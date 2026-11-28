import { render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../messages/en.json";

const replace = vi.fn();
const session = { status: "loading", currentUser: null, restoreFailed: false };

vi.mock("next/navigation", () => ({
  usePathname: () => "/org/milos/home",
  useRouter: () => ({ replace }),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => session }));
vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({ isLoading: false, membership: null, role: "member" }),
}));

import { AuthGuard } from "./auth-guard";

function renderGuard() {
  return render(
    <NextIntlClientProvider locale="en" messages={en}>
      <AuthGuard>
        <p>app</p>
      </AuthGuard>
    </NextIntlClientProvider>,
  );
}

beforeEach(() => {
  replace.mockReset();
  Object.assign(session, { status: "loading", restoreFailed: false });
});

describe("AuthGuard splash", () => {
  it("carries a way out that works without JavaScript, revealed by CSS after a delay", () => {
    renderGuard();
    const fallback = screen.getByTestId("splash-fallback");
    expect(fallback.className).toContain("splash-fallback");
    expect(screen.getByRole("link", { name: "Try again" }).getAttribute("href")).toBe("/org/milos/home");
    expect(screen.getByRole("link", { name: "Sign in again" }).getAttribute("href")).toBe(
      "/login?next=%2Forg%2Fmilos%2Fhome&restore=failed",
    );
  });

  it("sends a failed restore to sign in with the reason", () => {
    Object.assign(session, { status: "guest", restoreFailed: true });
    renderGuard();
    expect(replace).toHaveBeenCalledWith("/login?next=%2Forg%2Fmilos%2Fhome&restore=failed");
  });

  it("sends a plain guest to sign in without a reason", () => {
    Object.assign(session, { status: "guest", restoreFailed: false });
    renderGuard();
    expect(replace).toHaveBeenCalledWith("/login?next=%2Forg%2Fmilos%2Fhome");
  });
});
