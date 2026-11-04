"use client";

import type { RankColor } from "@/api/body-devices";
import { beltColor } from "@/lib/body-devices";

/**
 * A belt drawn from the theme's --belt-* tokens (ADR-377): the colour, the
 * black bar near the end where stripes sit, and the stripes earned. A level
 * without a colour shows as a plain muted bar.
 */
export function Belt({ color, stripes = 0, label, className = "h-4 w-28" }: { color: RankColor | null | undefined; stripes?: number; label?: string; className?: string }) {
  return (
    <span
      role={label ? "img" : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
      className={`relative inline-block shrink-0 rounded-sm ${className}`}
      style={{ background: beltColor(color), border: "1px solid var(--belt-edge)" }}
    >
      {color ? (
        <span className="absolute inset-y-0 right-2 flex w-8 items-center justify-end gap-0.5 px-0.5" style={{ background: "var(--belt-bar)" }}>
          {Array.from({ length: Math.min(stripes, 10) }, (_, index) => (
            <i key={index} className="block h-full w-0.5" style={{ background: "var(--belt-stripe)" }} />
          ))}
        </span>
      ) : null}
    </span>
  );
}
