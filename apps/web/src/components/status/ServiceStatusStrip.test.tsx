import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { fetchStatusOverview, type StatusOverview } from "@/api/service-status";
import { ServiceStatusStrip } from "@/components/status/ServiceStatusStrip";

let pathname = "/";
let user: { id: string } | null = { id: "u1" };
let memberships: Array<{ role: string }> = [{ role: "member" }];

vi.mock("next/navigation", () => ({ usePathname: () => pathname, useRouter: () => ({ refresh: vi.fn() }), useSearchParams: () => new URLSearchParams() }));
vi.mock("next-intl", () => ({ useLocale: () => "de", useTranslations: () => (key: string) => key }));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ currentUser: user }) }));
vi.mock("@/lib/organization-slug", () => ({ useOrganizationMemberships: () => ({ data: memberships }) }));
vi.mock("@/api/service-status", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/service-status")>()),
  fetchStatusOverview: vi.fn(),
}));

function overview(components: string[], resolved = false): StatusOverview {
  return {
    status: resolved ? "operational" : "partial_outage",
    components: [],
    upcoming: [],
    generated_at: "2026-11-02T19:30:00Z",
    active: resolved
      ? []
      : [
          {
            id: "i1",
            kind: "incident",
            title: "Καθυστερήσεις στα email",
            title_en: "Email delays",
            locale: "el",
            en_source: "edited",
            impact: "minor",
            status: "investigating",
            components: components as StatusOverview["active"][number]["components"],
            scheduled_for: null,
            scheduled_until: null,
            started_at: "2026-11-02T19:12:00Z",
            resolved_at: null,
            updates: [{ id: "u1", status: "investigating", body: "Το ερευνούμε.", body_en: "Receipts are delayed by up to an hour.", locale: "el", en_source: "edited", created_at: "2026-11-02T19:20:00Z" }],
          },
        ],
  };
}

function renderStrip() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <ServiceStatusStrip />
    </QueryClientProvider>,
  );
}

describe("ServiceStatusStrip (ADR-366)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    pathname = "/";
    user = { id: "u1" };
    memberships = [{ role: "member" }];
  });

  it("shows an active incident to a member who uses it, in English for a German reader, with no close button", async () => {
    vi.mocked(fetchStatusOverview).mockResolvedValue(overview(["email"]));
    renderStrip();
    const strip = await screen.findByTestId("service-status-strip");
    expect(strip.textContent).toContain("Email delays.");
    expect(strip.textContent).toContain("Receipts are delayed by up to an hour.");
    expect(screen.getByRole("link", { name: "stripDetails" }).getAttribute("href")).toBe("/status");
    expect(strip.querySelector("button")).toBeNull();
  });

  it("stays hidden for people who do not use the affected part, and once it is resolved", async () => {
    vi.mocked(fetchStatusOverview).mockResolvedValue(overview(["fiscal"]));
    const { unmount } = renderStrip();
    await vi.waitFor(() => expect(fetchStatusOverview).toHaveBeenCalled());
    expect(screen.queryByTestId("service-status-strip")).toBeNull();
    unmount();

    vi.mocked(fetchStatusOverview).mockResolvedValue(overview(["email"], true));
    renderStrip();
    await vi.waitFor(() => expect(fetchStatusOverview).toHaveBeenCalledTimes(2));
    expect(screen.queryByTestId("service-status-strip")).toBeNull();
  });

  it("never shows signed out or on the status page itself", () => {
    user = null;
    renderStrip();
    expect(fetchStatusOverview).not.toHaveBeenCalled();
    user = { id: "u1" };
    pathname = "/status";
    renderStrip();
    expect(fetchStatusOverview).not.toHaveBeenCalled();
  });
});
