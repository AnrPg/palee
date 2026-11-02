// ADR-365 / ADR-367, W7 screen 3: the state of «Λήψη των δεδομένων του box».
// Pure, so the card's states are unit tested.

export type ExportLike = {
  status: "pending" | "ready" | "failed" | "expired";
  requested_at: string;
  completed_at: string | null;
  expires_at: string | null;
  file: { bytes: number; download_url: string | null; name: string } | null;
  parts?: Array<{ bytes: number; download_url: string | null; name: string; files: number }>;
};

export type ExportCard<T extends ExportLike> =
  | { kind: "idle"; last: T | null }
  | { kind: "working"; export: T }
  | { kind: "ready"; export: T; totalBytes: number; canAskAgain: boolean }
  | { kind: "failed"; export: T };

/** One a day: a request less than 24 hours after the last one that did not fail waits (ADR-365). */
export const COOLDOWN_MS = 24 * 3_600_000;

export function latestExport<T extends ExportLike>(exports: T[] | undefined): T | null {
  if (!exports || exports.length === 0) return null;
  return [...exports].sort((a, b) => b.requested_at.localeCompare(a.requested_at))[0] ?? null;
}

export function exportCard<T extends ExportLike>(exports: T[] | undefined, now: number): ExportCard<T> {
  const latest = latestExport(exports);
  if (!latest) return { kind: "idle", last: null };
  if (latest.status === "pending") return { kind: "working", export: latest };
  if (latest.status === "failed") return { kind: "failed", export: latest };
  if (latest.status === "ready" && latest.file) {
    const totalBytes = latest.file.bytes + (latest.parts ?? []).reduce((sum, part) => sum + part.bytes, 0);
    return {
      kind: "ready",
      export: latest,
      totalBytes,
      canAskAgain: now - Date.parse(latest.requested_at) >= COOLDOWN_MS,
    };
  }
  return { kind: "idle", last: latest };
}

/** "184 MB", "3.2 GB", "820 KB": decimal units, as file managers show them. */
export function formatBytes(bytes: number, locale: string): string {
  const units = ["byte", "kilobyte", "megabyte", "gigabyte"] as const;
  let value = bytes;
  let unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit += 1;
  }
  return new Intl.NumberFormat(locale, {
    style: "unit",
    unit: units[unit],
    unitDisplay: "short",
    maximumFractionDigits: value < 10 && unit > 0 ? 1 : 0,
  }).format(value);
}
