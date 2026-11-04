import { render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";

// ANR 2026-11-04 (option A): Μάρκετινγκ is the home of challenges, the box's
// promotions, partner perks and referrals; each tile shows to whoever may open it.

const access = vi.hoisted(() => ({ capabilities: {} as Record<string, string> | null, loading: false }));
const api = vi.hoisted(() => ({
  fetchAdminChallenges: vi.fn(async () => ({
    challenges: [
      { id: "c1", starts_at: "2000-01-01T00:00:00Z", ends_at: "2999-01-01T00:00:00Z", progress_summary: { participants: 40 } },
      { id: "c2", starts_at: "2000-01-01T00:00:00Z", ends_at: "2999-01-01T00:00:00Z", progress_summary: { participants: 24 } },
      { id: "c3", starts_at: "2000-01-01T00:00:00Z", ends_at: "2000-02-01T00:00:00Z", progress_summary: { participants: 99 } },
    ],
  })),
  fetchPromotionCampaigns: vi.fn(async () => ({ promotion_campaigns: [{ id: "p1", active: true }, { id: "p2", active: false }] })),
  fetchStaffPerks: vi.fn(async () => [
    { id: "k1", status: "published", valid_from: null, valid_until: null, uses_count: 30 },
    { id: "k2", status: "draft", valid_from: null, valid_until: null, uses_count: 11 },
  ]),
  fetchStaffReferrals: vi.fn(async () => ({ invites: [], stats: { open: 2, qualified: 9 } })),
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" } }),
}));
vi.mock("@/lib/organization-slug", () => ({
  useOrganizationSlug: () => "kypseli",
  adminHref: (href: string, slug: string | null) => (slug ? `/org/${slug}${href}` : href),
}));
vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({
    membership: access.capabilities ? { role: "admin", capabilities: access.capabilities } : null,
    isLoading: access.loading,
  }),
}));
vi.mock("@/api/challenges", () => ({ fetchAdminChallenges: api.fetchAdminChallenges }));
vi.mock("@/api/finance", () => ({ fetchPromotionCampaigns: api.fetchPromotionCampaigns }));
vi.mock("@/api/perks", async (original) => ({ ...(await original<object>()), fetchStaffPerks: api.fetchStaffPerks }));
vi.mock("@/api/referrals", async (original) => ({ ...(await original<object>()), fetchStaffReferrals: api.fetchStaffReferrals }));

import { MarketingTab } from "./MarketingTab";

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en}>
        <MarketingTab />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const ALL = {
  manage_challenges: "all",
  manage_promotions: "all",
  manage_perks: "all",
  view_finance_reports: "all",
};

describe("MarketingTab", () => {
  beforeEach(() => {
    access.capabilities = ALL;
    access.loading = false;
    Object.values(api).forEach((mock) => mock.mockClear());
  });

  it("opens each area at its new home, Packages in Finance", () => {
    wrap();
    const href = (id: string) => screen.getByTestId(`marketing-tile-${id}`).getAttribute("href");
    expect(href("challenges")).toBe("/org/kypseli/admin/marketing/challenges");
    expect(href("promotions")).toBe("/org/kypseli/admin/marketing/promotions");
    expect(href("perks")).toBe("/org/kypseli/admin/marketing/perks");
    expect(href("referrals")).toBe("/org/kypseli/admin/marketing/referrals");
    expect(href("packages")).toBe("/org/kypseli/admin/finance?tab=packages");
    expect(screen.getByTestId("marketing-tile-packages")).toHaveTextContent(en.MarketingHub.inFinance);
  });

  it("shows one live number per tile from the lists they open", async () => {
    wrap();
    expect(await screen.findByTestId("marketing-stat-challenges")).toHaveTextContent("2 active · 64 participants");
    expect(await screen.findByTestId("marketing-stat-promotions")).toHaveTextContent("1 active");
    expect(await screen.findByTestId("marketing-stat-perks")).toHaveTextContent("1 active · 41 redemptions");
    expect(await screen.findByTestId("marketing-stat-referrals")).toHaveTextContent("9 referrals counted in the last 90 days");
  });

  it("shows only the areas the role may open, and asks nothing of the others", async () => {
    access.capabilities = { manage_perks: "all" };
    wrap();
    expect(await screen.findByTestId("marketing-stat-perks")).toBeInTheDocument();
    expect(screen.queryByTestId("marketing-tile-challenges")).toBeNull();
    expect(screen.queryByTestId("marketing-tile-promotions")).toBeNull();
    expect(screen.queryByTestId("marketing-tile-referrals")).toBeNull();
    expect(screen.queryByTestId("marketing-tile-packages")).toBeNull();
    expect(api.fetchAdminChallenges).not.toHaveBeenCalled();
    expect(api.fetchPromotionCampaigns).not.toHaveBeenCalled();
    expect(api.fetchStaffReferrals).not.toHaveBeenCalled();
  });

  it("view_promotions opens promotions and referrals", () => {
    access.capabilities = { view_promotions: "all" };
    wrap();
    expect(screen.getByTestId("marketing-tile-promotions")).toBeInTheDocument();
    expect(screen.getByTestId("marketing-tile-referrals")).toBeInTheDocument();
    expect(screen.queryByTestId("marketing-tile-perks")).toBeNull();
  });

  it("says so calmly when nothing opens, and waits for the memberships", () => {
    access.capabilities = { check_in: "all" };
    const { unmount } = wrap();
    expect(screen.getByText(en.MarketingHub.empty)).toBeInTheDocument();
    unmount();
    access.loading = true;
    wrap();
    expect(screen.queryByTestId("marketing-tiles")).toBeNull();
    expect(screen.queryByText(en.MarketingHub.empty)).toBeNull();
  });
});
