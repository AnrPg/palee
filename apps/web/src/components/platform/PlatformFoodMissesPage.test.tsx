import { render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";

import { PlatformFoodMissesPage } from "./PlatformFoodMissesPage";

const fetchBarcodeMisses = vi.fn();

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string, values?: Record<string, unknown>) => (values ? `${key}:${Object.values(values).join(",")}` : key),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "tok" } }) }));
vi.mock("@/components/ui/BackLink", () => ({ BackLink: ({ children }: { children: ReactNode }) => <a>{children}</a> }));
vi.mock("@/api/body-devices", () => ({ fetchBarcodeMisses: (...args: unknown[]) => fetchBarcodeMisses(...args) }));

const wrapper = ({ children }: { children: ReactNode }) => (
  <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>{children}</QueryClientProvider>
);

describe("PlatformFoodMissesPage (ADR-421)", () => {
  it("lists barcodes nobody had with their country and scans, and offers the countries seen", async () => {
    fetchBarcodeMisses.mockResolvedValue([
      { barcode: "5201234500006", country: "GR", scans: 4, first_seen_on: "2026-11-01", last_seen_on: "2026-11-03" },
      { barcode: "5201234500013", country: "", scans: 1, first_seen_on: "2026-11-02", last_seen_on: "2026-11-02" },
    ]);
    render(<PlatformFoodMissesPage />, { wrapper });
    expect(await screen.findByText("5201234500006")).toBeInTheDocument();
    expect(screen.getByText("scans:4")).toBeInTheDocument();
    expect(screen.getByText(/noCountry/)).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "GR" })).toBeInTheDocument();
    expect(fetchBarcodeMisses).toHaveBeenCalledWith("tok", null);
  });

  it("shows the empty state", async () => {
    fetchBarcodeMisses.mockResolvedValue([]);
    render(<PlatformFoodMissesPage />, { wrapper });
    expect(await screen.findByText("empty")).toBeInTheDocument();
  });
});
