"use client";

import { useId, type ReactNode } from "react";

import { buttonRow } from "./rows";

/**
 * Ask on the page before a destructive step: the question, then «keep» and
 * the step itself. No browser dialog and no sheet, for small reversible-ish
 * steps (unfollow, remove, withdraw).
 *
 * It always fits a phone (ANR 2026-11-07): the question wraps, the buttons
 * share one line while they fit and stack when they don't, and the element
 * carries `data-inline-confirm` so a host row built with `ui/rows`
 * (`itemRowActions`) gives it the whole line.
 */
export function InlineConfirm({
  question,
  cancelLabel,
  confirmLabel,
  onCancel,
  onConfirm,
  busy = false,
  tone = "danger",
  framed = false,
  className = "",
  testId,
}: {
  question: ReactNode;
  cancelLabel: ReactNode;
  confirmLabel: ReactNode;
  onCancel: () => void;
  onConfirm: () => void;
  busy?: boolean;
  /** `danger` for a destructive step, `primary` for a weighty but safe one. */
  tone?: "danger" | "primary";
  /** A raised panel around it, for a confirm that opens inside a busy card. */
  framed?: boolean;
  className?: string;
  testId?: string;
}) {
  const id = useId();
  const button = "min-h-11 min-w-0 grow basis-auto rounded-2xl px-4 text-center text-sm font-bold disabled:opacity-50";
  return (
    <div
      role="group"
      aria-labelledby={id}
      data-inline-confirm=""
      data-testid={testId}
      className={`flex w-full min-w-0 flex-col gap-2 ${framed ? "rounded-2xl p-3" : ""} ${className}`}
      style={framed ? { background: "var(--panel-raised)", border: "1px solid var(--border)" } : undefined}
    >
      <p id={id} className="text-sm [overflow-wrap:anywhere]" style={{ color: framed ? "var(--text)" : "var(--text-soft)" }}>
        {question}
      </p>
      <div className={buttonRow}>
        <button type="button" className={button} style={{ border: "1px solid var(--border)", color: "var(--text)" }} onClick={onCancel}>
          {cancelLabel}
        </button>
        <button
          type="button"
          disabled={busy}
          className={button}
          style={
            tone === "danger"
              ? { background: "var(--danger)", color: "var(--danger-contrast)" }
              : { background: "var(--primary)", color: "var(--primary-contrast)" }
          }
          onClick={onConfirm}
        >
          {confirmLabel}
        </button>
      </div>
    </div>
  );
}
