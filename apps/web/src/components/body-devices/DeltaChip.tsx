"use client";

import { useTranslations } from "next-intl";

import { deltaTone, formatDelta } from "@/lib/body-devices";

/** «−0:05 μπροστά» / «+0:12 πίσω»: words without judgement (mockup d7res). */
export function DeltaChip({ deltaMs, bare = false }: { deltaMs: number; bare?: boolean }) {
  const t = useTranslations("BodyDevices");
  const tone = deltaTone(deltaMs);
  const color = tone === "ahead" ? "var(--success)" : tone === "behind" ? "var(--warning)" : "var(--text-soft)";
  const text = formatDelta(deltaMs);
  return (
    <span
      className="shrink-0 rounded-full px-2.5 py-0.5 text-xs font-bold tabular-nums"
      style={{ background: `color-mix(in srgb, ${color} 16%, transparent)`, color }}
    >
      {bare || tone === "level" ? (tone === "level" ? t("delta.level") : text) : t(`delta.${tone}`, { delta: text })}
    </span>
  );
}
