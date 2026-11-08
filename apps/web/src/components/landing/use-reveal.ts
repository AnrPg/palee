"use client";

import { useEffect, type RefObject } from "react";

/**
 * Shows each `.landing-reveal` inside `root` once it scrolls into view
 * (ADR-555). `key` re-runs the search when the content under `root` is
 * swapped, as the business landing does when the audience changes.
 */
export function useReveal(root: RefObject<HTMLElement | null>, key?: unknown) {
  useEffect(() => {
    const host = root.current;
    if (!host) return;
    const targets = Array.from(host.querySelectorAll<HTMLElement>(".landing-reveal:not([data-shown])"));
    if (typeof IntersectionObserver === "undefined") {
      for (const target of targets) target.dataset.shown = "true";
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          (entry.target as HTMLElement).dataset.shown = "true";
          observer.unobserve(entry.target);
        }
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.12 },
    );
    for (const target of targets) observer.observe(target);
    return () => observer.disconnect();
  }, [root, key]);
}
