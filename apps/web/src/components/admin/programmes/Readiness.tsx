"use client";

import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";

import { primaryButtonClass, primaryButtonStyle } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";

import { useWeekList } from "./editor-ui";
import { readinessTarget, type ReadinessItem, type ReadinessTarget } from "./programme-editor-model";

/**
 * «Λείπουν N πράγματα» (ADR-544): a calm list of what the draft still lacks,
 * each item taking the coach there, instead of an error on «Δημοσίευση».
 */
function useReadinessText() {
  const t = useTranslations("Programmes.editor2");
  const locale = useLocale();
  const list = useWeekList();
  return {
    label: (item: ReadinessItem) =>
      item.key === "empty_weeks"
        ? t("ready.empty_weeks", { count: item.weeks.length, weeks: list(item.weeks, locale) })
        : item.key === "title" || item.key === "days" || item.key === "summary"
          ? t(`ready.${item.key}`)
          : "",
    hint: (item: ReadinessItem) => (item.key === "title" ? t("readyHint.title") : item.key === "summary" ? t("readyHint.summary") : t("readyHint.weeks")),
  };
}

/** Phone (board 1κ A): the bar at the bottom with «Δες τι λείπει» and «Δημοσίευση…». */
export function ReadinessBar({
  items,
  publishLabel,
  onPublish,
  onGo,
}: {
  items: ReadinessItem[];
  publishLabel: string | null;
  onPublish: () => void;
  onGo: (target: ReadinessTarget) => void;
}) {
  const t = useTranslations("Programmes.editor2");
  const text = useReadinessText();
  const [open, setOpen] = useState(false);
  if (items.length === 0 && !publishLabel) return null;
  return (
    <div
      className="sticky z-10 -mx-4 flex items-center gap-3 px-4 py-3"
      style={{ bottom: "var(--bottom-nav-space, 0px)", background: "var(--panel)", borderTop: "1px solid var(--border)", paddingBottom: "max(0.75rem, env(safe-area-inset-bottom))" }}
      data-testid="programme-readiness-bar"
    >
      <div className="min-w-0 flex-1">
        <b className="block text-sm" style={{ color: "var(--text)" }}>
          {items.length ? t("readyCount", { count: items.length }) : t("readyToPublish")}
        </b>
        {items.length ? (
          <button type="button" onClick={() => setOpen(true)} className="min-h-6 text-xs font-semibold underline" style={{ color: "var(--primary)" }} data-testid="programme-readiness-open">
            {t("readySee")}
          </button>
        ) : null}
      </div>
      {publishLabel ? (
        <button type="button" className={primaryButtonClass} style={primaryButtonStyle} onClick={onPublish} data-testid="programme-publish-open">
          {publishLabel}
        </button>
      ) : null}
      {open ? (
        <Dialog onClose={() => setOpen(false)} title={t("readyTitle")} size="sm" testId="programme-readiness">
          <ul className="flex flex-col gap-1">
            {items.map((item) => {
              const target = readinessTarget(item);
              return (
                <li key={item.key}>
                  <button
                    type="button"
                    disabled={!target}
                    onClick={() => {
                      setOpen(false);
                      if (target) onGo(target);
                    }}
                    className="flex min-h-12 w-full flex-col justify-center rounded-xl px-3 py-2 text-start"
                    style={{ color: "var(--text)" }}
                    data-testid={`programme-readiness-${item.key}`}
                  >
                    <span className="flex items-center gap-2 text-sm font-semibold">
                      <i aria-hidden="true" className="inline-block h-2 w-2 shrink-0 rounded-full" style={{ background: item.blocking ? "var(--danger)" : "var(--warning)" }} />
                      {text.label(item)}
                    </span>
                    <span className="ps-4 text-xs" style={{ color: "var(--muted)" }}>{text.hint(item)}</span>
                  </button>
                </li>
              );
            })}
          </ul>
        </Dialog>
      ) : null}
    </div>
  );
}

/** Desktop (board 1μ A): one line above the grid with «Πήγαινε στο πρώτο». */
export function ReadinessBanner({ items, onGo }: { items: ReadinessItem[]; onGo: (target: ReadinessTarget) => void }) {
  const t = useTranslations("Programmes.editor2");
  const text = useReadinessText();
  if (items.length === 0) return null;
  const first = items.map(readinessTarget).find(Boolean) ?? null;
  return (
    <div
      className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-2xl px-4 py-2.5 text-sm"
      style={{ background: "color-mix(in srgb, var(--warning) 10%, var(--panel))", border: "1px solid color-mix(in srgb, var(--warning) 35%, var(--border))", color: "var(--text)" }}
      role="note"
      data-testid="programme-readiness-banner"
    >
      <span className="min-w-0 flex-1">
        <b>{t("readyLead")}</b> {items.map((item) => text.label(item)).join(" · ")}
      </span>
      {first ? (
        <button type="button" onClick={() => onGo(first)} className="text-sm font-semibold" style={{ color: "var(--primary)" }} data-testid="programme-readiness-first">
          {t("readyGoFirst")}
        </button>
      ) : null}
    </div>
  );
}
