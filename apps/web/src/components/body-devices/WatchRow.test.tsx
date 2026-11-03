import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { WatchRows } from "./WatchRow";

const fetchWatches = vi.fn();
const saveWatchSettings = vi.fn();

vi.mock("next-intl", () => ({ useTranslations: () => (key: string) => key }));
vi.mock("@/api/body-devices", () => ({
  WATCHES_KEY: ["body-devices", "watches"],
  fetchWatches: (...args: unknown[]) => fetchWatches(...args),
  saveWatchSettings: (...args: unknown[]) => saveWatchSettings(...args),
  unpairWatch: vi.fn(),
}));

const watch = {
  platform: "apple_watch",
  device_name: "Apple Watch της Μαρίας",
  contract_version: 1,
  needs_upgrade: false,
  settings: { show_heart_rate: true, show_pace: true, haptics: true, max_hr: null },
};

function renderRows() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  render(<ul><WatchRows token="tok" /></ul>, { wrapper });
}

describe("WatchRows (mockup d8pair A)", () => {
  beforeEach(() => {
    fetchWatches.mockReset();
    saveWatchSettings.mockReset();
  });

  it("says pairing happens from the phone when there is no watch", async () => {
    fetchWatches.mockResolvedValue({ watches: [] });
    renderRows();
    expect(await screen.findByText("watch.fromPhone")).toBeInTheDocument();
  });

  it("opens the settings and saves a switch", async () => {
    fetchWatches.mockResolvedValue({ watches: [watch] });
    saveWatchSettings.mockResolvedValue({ ...watch, settings: { ...watch.settings, haptics: false } });
    renderRows();
    fireEvent.click(await screen.findByText("Apple Watch της Μαρίας"));
    expect(await screen.findByTestId("watch-settings")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("switch", { name: /watch.haptics/ }));
    await waitFor(() => expect(saveWatchSettings).toHaveBeenCalledWith("tok", watch, { haptics: false }));
  });

  it("keeps the maximum heart rate behind «Προχωρημένα» and holds it within 120–230", async () => {
    fetchWatches.mockResolvedValue({ watches: [watch] });
    saveWatchSettings.mockResolvedValue({ ...watch, settings: { ...watch.settings, max_hr: 230 } });
    renderRows();
    fireEvent.click(await screen.findByText("Apple Watch της Μαρίας"));
    expect(screen.queryByText("watch.maxHr")).not.toBeInTheDocument();
    fireEvent.click(screen.getByText("advanced"));
    const field = screen.getByLabelText(/watch.maxHr/);
    fireEvent.focus(field);
    fireEvent.change(field, { target: { value: "300" } });
    fireEvent.blur(field);
    await waitFor(() => expect(saveWatchSettings).toHaveBeenCalledWith("tok", watch, { max_hr: 230 }));
  });
});
