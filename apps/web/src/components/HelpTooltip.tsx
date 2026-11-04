"use client";

import { useId, useRef, useState, type ReactNode } from "react";

import { Popover } from "@/components/ui/Popover";

/**
 * Every «?» infobox trigger looks the same and stays quiet (ANR 2026-11-04):
 * no fill and no accent colour, only a hairline ring and a muted glyph from
 * the theme, so it never competes with the number or title it explains.
 * Hover and keyboard focus raise it to the soft text colour.
 */
export const HELP_ICON_CLASS =
  "inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[11px] font-semibold " +
  "text-[var(--muted)] transition-colors hover:text-[var(--text-soft)] focus-visible:text-[var(--text-soft)]";
export const HELP_ICON_STYLE = {
  background: "transparent",
  border: "1px solid var(--border-strong)",
};

/**
 * The «?» of a widget whose infobox holds more than a sentence, or an action
 * (ADR-462: a metric's reset sits in its infobox footer). A tap opens it on
 * the popover layer, so it never takes space or moves anything on the page.
 * `footer` gets `close`, to close the box before opening a dialog.
 */
export function HelpPopover({
  label,
  children,
  footer,
  helpKey,
}: {
  label: string;
  children: ReactNode;
  footer?: (close: () => void) => ReactNode;
  /** Names the help text, so a page can check that no two widgets share one. */
  helpKey?: string;
}) {
  const id = useId();
  const anchorRef = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const close = () => setOpen(false);
  const footerContent = footer?.(close);

  return (
    <>
      <button
        ref={anchorRef}
        type="button"
        aria-label={label}
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-controls={open ? id : undefined}
        data-help-key={helpKey}
        onClick={() => setOpen((current) => !current)}
        className={HELP_ICON_CLASS}
        style={HELP_ICON_STYLE}
      >
        ?
      </button>
      <Popover
        anchorRef={anchorRef}
        open={open}
        onClose={close}
        role="dialog"
        id={id}
        ariaLabel={label}
        width={300}
        className="rounded-xl text-start text-xs font-normal normal-case leading-5 tracking-normal shadow-xl"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
      >
        <div className="px-3 py-2.5">{children}</div>
        {footerContent ? (
          <div className="flex justify-end px-3 py-2" style={{ borderTop: "1px solid var(--border)" }}>
            {footerContent}
          </div>
        ) : null}
      </Popover>
    </>
  );
}

export function HelpTooltip({ label, children }: { label: string; children: React.ReactNode }) {
  const id = useId();
  const [open, setOpen] = useState(false);

  return (
    <span className="group relative inline-flex align-middle">
      <button
        aria-describedby={open ? id : undefined}
        aria-expanded={open}
        aria-label={label}
        className={HELP_ICON_CLASS}
        onBlur={() => setOpen(false)}
        onClick={() => setOpen((current) => !current)}
        onFocus={() => setOpen(true)}
        type="button"
        style={HELP_ICON_STYLE}
      >
        ?
      </button>
      <span
        id={id}
        role="tooltip"
        className={`${open ? "visible opacity-100" : "invisible opacity-0 group-hover:visible group-hover:opacity-100"} pointer-events-none absolute start-1/2 top-full z-(--z-popover) mt-2 w-64 -translate-x-1/2 rounded-xl px-3 py-2 text-start text-xs font-normal normal-case leading-5 tracking-normal shadow-xl transition-opacity`}
        style={{
          background: "var(--panel-raised)",
          border: "1px solid var(--border-strong)",
          color: "var(--text-soft)",
        }}
      >
        {children}
      </span>
    </span>
  );
}

const HINT_POSITION_CLASSES = { start: "start-0", center: "", end: "end-0" } as const;
// Physical centering works in both LTR and RTL layouts.
const CENTERED_HINT_STYLE = { left: "50%", transform: "translateX(-50%)" };

/**
 * Hover/focus infobox for compact controls (icon-only or emoji buttons).
 * Wrap the control; the hint appears below it on hover or keyboard focus.
 */
export function HoverHint({
  hint,
  align = "center",
  suppressed = false,
  children,
}: {
  hint: React.ReactNode;
  align?: "start" | "center" | "end";
  /** Keep the hint hidden, e.g. while the wrapped control's own menu is open. */
  suppressed?: boolean;
  children: React.ReactNode;
}) {
  const position = HINT_POSITION_CLASSES[align];

  return (
    <span className="group/hint relative inline-flex">
      {children}
      <span
        role="tooltip"
        className={`pointer-events-none invisible absolute top-full z-(--z-popover) mt-2 w-max max-w-56 rounded-lg px-2.5 py-1.5 text-start text-xs font-medium normal-case leading-5 tracking-normal opacity-0 shadow-xl transition-opacity delay-150 ${suppressed ? "" : "group-hover/hint:visible group-hover/hint:opacity-100 group-has-[:focus-visible]/hint:visible group-has-[:focus-visible]/hint:opacity-100"} ${position}`}
        style={{
          ...(align === "center" ? CENTERED_HINT_STYLE : null),
          background: "var(--panel-raised)",
          border: "1px solid var(--border-strong)",
          color: "var(--text-soft)",
        }}
      >
        {hint}
      </span>
    </span>
  );
}
