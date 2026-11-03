import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiError } from "@/api/client";
import { fetchBoxDataExports, requestBoxDataExport, type BoxDataExport } from "@/api/box-data-exports";
import { BoxDataExportCard } from "@/components/admin/BoxDataExportCard";

vi.mock("next-intl", () => ({
  useLocale: () => "el",
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
}));
vi.mock("@/api/box-data-exports", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/box-data-exports")>()),
  fetchBoxDataExports: vi.fn(),
  requestBoxDataExport: vi.fn(),
}));

const ready: BoxDataExport = {
  id: "e1",
  status: "ready",
  record_count: 1200,
  table_count: 80,
  requested_at: new Date(Date.now() - 3_600_000).toISOString(),
  completed_at: new Date(Date.now() - 3_000_000).toISOString(),
  expires_at: new Date(Date.now() + 6 * 86_400_000).toISOString(),
  file: { name: "palee-kypseli-data.zip", bytes: 4_000_000, sha256: "x", download_url: "https://objects.test/data.zip" },
  parts: [{ name: "palee-kypseli-files-1.zip", bytes: 180_000_000, sha256: "y", files: 120, download_url: "https://objects.test/files-1.zip" }],
};

function renderCard() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <BoxDataExportCard token="token" slug="kypseli" email="apostolos@example.com" />
    </QueryClientProvider>,
  );
}

describe("BoxDataExportCard (ADR-365/367, W7 screen 3)", () => {
  beforeEach(() => vi.clearAllMocks());

  it("idle: one button prepares the file", async () => {
    vi.mocked(fetchBoxDataExports).mockResolvedValueOnce([]).mockResolvedValue([{ ...ready, status: "pending", file: null, parts: [] }]);
    vi.mocked(requestBoxDataExport).mockResolvedValue({ ...ready, status: "pending", file: null, parts: [] });
    renderCard();
    expect(await screen.findByText("lastNone")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "prepare" }));
    await waitFor(() => expect(requestBoxDataExport).toHaveBeenCalledWith("token"));
    expect(await screen.findByText('workingEmail:{"email":"apostolos@example.com"}')).toBeTruthy();
    expect(screen.getByTestId("box-data-export").dataset.state).toBe("working");
  });

  it("ready: «Λήψη ZIP», the size of everything, the photo parts and a new file tomorrow", async () => {
    vi.mocked(fetchBoxDataExports).mockResolvedValue([ready]);
    renderCard();
    const download = await screen.findByTestId("box-data-export-download");
    expect(download.getAttribute("href")).toBe("https://objects.test/data.zip");
    expect(download.textContent).toBe("download");
    expect(screen.getByTestId("box-data-export").textContent).toContain("184 MB");
    expect(screen.getByTestId("box-data-export-parts").textContent).toContain('partsIntro:{"count":1}');
    expect(screen.getByText("againTomorrow")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "prepare" })).toBeNull();
  });

  it("says plainly when a file was already asked for today", async () => {
    vi.mocked(fetchBoxDataExports).mockResolvedValue([{ ...ready, status: "failed", file: null, parts: [] }]);
    vi.mocked(requestBoxDataExport).mockRejectedValue(new ApiError(409, "soon", { code: "box_export_too_soon" }));
    renderCard();
    fireEvent.click(await screen.findByRole("button", { name: "prepare" }));
    expect(await screen.findByText("tooSoon")).toBeTruthy();
  });
});
