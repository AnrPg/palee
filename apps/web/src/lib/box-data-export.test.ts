import { describe, expect, it } from "vitest";

import { COOLDOWN_MS, exportCard, formatBytes, type ExportLike } from "@/lib/box-data-export";

const now = Date.parse("2026-11-02T22:00:00Z");
const base: ExportLike = {
  status: "ready",
  requested_at: "2026-11-02T21:30:00Z",
  completed_at: "2026-11-02T21:40:00Z",
  expires_at: "2026-11-09T21:40:00Z",
  file: { bytes: 4_000_000, download_url: "https://x/data.zip", name: "data.zip" },
  parts: [{ bytes: 180_000_000, download_url: "https://x/files-1.zip", name: "files-1.zip", files: 120 }],
};

describe("box data export card (ADR-365/367)", () => {
  it("is idle without an export, or after one expired", () => {
    expect(exportCard([], now)).toEqual({ kind: "idle", last: null });
    expect(exportCard([{ ...base, status: "expired" }], now).kind).toBe("idle");
  });

  it("works while the newest is pending; offers a retry after a failure", () => {
    const older = { ...base, requested_at: "2026-10-01T10:00:00Z" };
    expect(exportCard([older, { ...base, status: "pending", file: null }], now).kind).toBe("working");
    expect(exportCard([{ ...base, status: "failed", file: null }], now).kind).toBe("failed");
  });

  it("when ready: the size of every file, and a new one only the next day", () => {
    const card = exportCard([base], now);
    expect(card).toMatchObject({ kind: "ready", totalBytes: 184_000_000, canAskAgain: false });
    expect(exportCard([base], Date.parse(base.requested_at) + COOLDOWN_MS)).toMatchObject({ canAskAgain: true });
  });

  it("formats sizes in decimal units", () => {
    expect(formatBytes(184_000_000, "en")).toBe("184 MB");
    expect(formatBytes(3_200_000_000, "en")).toBe("3.2 GB");
    expect(formatBytes(820, "en")).toBe("820 byte");
  });
});
