"use client";

import { useId, useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import { HoverHint } from "@/components/HelpTooltip";

/** One part of an info box: a short heading and its text. */
export type ExplainedPart = { heading: string; text: string };

/**
 * One advanced option with its explanation (ADR-490). The ⓘ next to the label
 * shows a one-line tooltip on hover or keyboard focus; a press (the only way on
 * a touch screen, which has no hover) opens an info box under the option with
 * the full explanation, and a second press closes it.
 */
export function ExplainedSetting({
  label,
  tip,
  parts,
  children,
  stacked = false,
}: {
  label: ReactNode;
  /** The tooltip: what the option does, in one sentence. */
  tip: string;
  /** The info box: what it does, what members see, when to change it. */
  parts: ExplainedPart[];
  /** The control. */
  children: ReactNode;
  /** Put the control under the label (chip groups) instead of beside it. */
  stacked?: boolean;
}) {
  const t = useTranslations("ExplainedSetting");
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const name = typeof label === "string" ? label : tip;

  return (
    <div className="flex flex-col gap-2" data-explained-setting>
      <div className={stacked ? "flex flex-col gap-2" : "flex flex-wrap items-center justify-between gap-x-3 gap-y-2"}>
        <span className="flex items-center gap-1.5 font-semibold" style={{ color: "var(--text-soft)" }}>
          {label}
          <HoverHint hint={tip} align="start" suppressed={open}>
            {/* Subtle on purpose (ANR 2026-11-04): a small outlined ⓘ in the muted text colour, no fill;
                the invisible padding keeps a usable tap target on phones. */}
            <button
              type="button"
              aria-expanded={open}
              aria-controls={panelId}
              aria-label={t("about", { name })}
              onClick={() => setOpen((value) => !value)}
              className="-m-1 inline-flex items-center justify-center rounded-full p-1 opacity-70 transition-opacity hover:opacity-100 focus-visible:opacity-100"
              style={{ color: open ? "var(--primary-strong)" : "var(--dim)" }}
            >
              <svg aria-hidden="true" viewBox="0 0 16 16" width="11" height="11" fill="none" stroke="currentColor" strokeWidth="1.5">
                <circle cx="8" cy="8" r="6.75" />
                <path d="M8 7.25v4" strokeLinecap="round" />
                <circle cx="8" cy="4.9" r="0.6" fill="currentColor" stroke="none" />
              </svg>
            </button>
          </HoverHint>
        </span>
        {children}
      </div>
      {open ? (
        <div
          id={panelId}
          role="note"
          className="flex flex-col gap-2 rounded-xl px-3 py-2.5 text-xs leading-5"
          style={{
            background: "color-mix(in srgb, var(--primary) 7%, var(--bg))",
            border: "1px solid color-mix(in srgb, var(--primary) 22%, transparent)",
            color: "var(--text-soft)",
          }}
        >
          {parts.map((part) => (
            <p key={part.heading}>
              <span className="font-semibold" style={{ color: "var(--text)" }}>
                {part.heading}
              </span>{" "}
              {part.text}
            </p>
          ))}
        </div>
      ) : null}
    </div>
  );
}
