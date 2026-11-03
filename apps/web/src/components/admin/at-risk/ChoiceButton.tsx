"use client";

import { useRef, useState, type CSSProperties } from "react";

import { Popover } from "@/components/ui/Popover";

/** A button that opens a short list of choices (a channel, a number of days); one tap picks. */
export function ChoiceButton<T extends string | number>({
  label,
  choices,
  onPick,
  disabled,
  style,
  testId,
}: {
  label: string;
  choices: Array<{ value: T; label: string }>;
  onPick: (value: T) => void;
  disabled?: boolean;
  style: CSSProperties;
  testId?: string;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLButtonElement>(null);
  return (
    <div className="relative shrink-0">
      <button
        ref={ref}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        disabled={disabled}
        data-testid={testId}
        onClick={() => setOpen((value) => !value)}
        className="min-h-10 rounded-full px-4 text-sm font-semibold disabled:opacity-50"
        style={style}
      >
        {label}
      </button>
      <Popover
        anchorRef={ref}
        open={open}
        onClose={() => setOpen(false)}
        align="end"
        minWidth={180}
        className="rounded-2xl py-1 shadow-lg"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <ul role="menu" aria-label={label}>
          {choices.map((choice) => (
            <li key={String(choice.value)} role="none">
              <button
                type="button"
                role="menuitem"
                onClick={() => {
                  setOpen(false);
                  onPick(choice.value);
                }}
                className="block min-h-11 w-full px-4 text-start text-sm font-semibold"
                style={{ color: "var(--text)" }}
              >
                {choice.label}
              </button>
            </li>
          ))}
        </ul>
      </Popover>
    </div>
  );
}
