"use client";

import Link from "next/link";

import type { SectionGroup } from "@/lib/role-navigation";
import { activeItemId } from "@/lib/role-navigation";
import { LockIcon } from "@/components/ui/LockIcon";

// The tab strip of a page group (Coaching, Training, Journal): each tab is an
// existing page, so the pages themselves stay as they are (ADR-103).
export function SectionTabs({
  group,
  pathname,
  hrefFor,
  labelFor,
  inset = "px-2 sm:px-5",
  lockedLabel,
}: {
  group: SectionGroup;
  pathname: string;
  hrefFor: (href: string, scoped?: boolean) => string;
  labelFor: (labelKey: string) => string;
  /** Side padding: the member bar lines the first tab up with its logo. */
  inset?: string;
  /** ADR-551: why a locked tab is shut (its tooltip and accessible name). */
  lockedLabel?: string;
}) {
  const active = activeItemId(pathname, group.tabs);
  return (
    <nav
      data-tabs
      aria-label={labelFor(group.id)}
      className={`flex w-full items-center gap-1 overflow-x-auto pb-1.5 ${inset}`}
      style={{ scrollbarWidth: "none" }}
    >
      {group.tabs.map((tab) => {
        const current = tab.id === active;
        if (tab.locked) {
          return (
            <span
              key={tab.id}
              role="link"
              aria-disabled="true"
              aria-label={lockedLabel ? `${labelFor(tab.labelKey)}. ${lockedLabel}` : labelFor(tab.labelKey)}
              title={lockedLabel}
              className="flex shrink-0 cursor-not-allowed items-center gap-1 whitespace-nowrap rounded-full px-3 py-1 text-xs font-semibold opacity-50"
              style={{ color: "var(--dim)", border: "1px solid var(--border)" }}
            >
              {labelFor(tab.labelKey)}
              <LockIcon size={11} />
            </span>
          );
        }
        return (
          // Full prefetch: switching tabs renders from the client cache with
          // no server round trip (staleTimes in next.config.ts).
          <Link
            key={tab.id}
            href={hrefFor(tab.href, tab.scoped)}
            prefetch
            aria-current={current ? "page" : undefined}
            className="shrink-0 whitespace-nowrap rounded-full px-3 py-1 text-xs font-semibold transition-colors"
            style={{
              background: current ? "color-mix(in srgb, var(--primary) 14%, transparent)" : "transparent",
              color: current ? "var(--primary-strong)" : "var(--dim)",
              border: `1px solid ${current ? "color-mix(in srgb, var(--primary) 30%, transparent)" : "var(--border)"}`,
            }}
          >
            {labelFor(tab.labelKey)}
          </Link>
        );
      })}
    </nav>
  );
}
