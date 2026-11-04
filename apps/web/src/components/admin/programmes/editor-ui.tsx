"use client";

import { useTranslations } from "next-intl";
import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from "react";

import { useWorkoutTypeLabels } from "@/components/workouts/WorkoutTypeSelect";
import { workoutTypeColor } from "@/lib/theme";

import type { LibraryWod } from "./programme-editor-model";

/** The desktop layout (board 1μ A) from `lg` up; phones and tablets get 1κ A. */
const DESKTOP_QUERY = "(min-width: 1024px)";

function subscribe(onChange: () => void) {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") return () => undefined;
  const query = window.matchMedia(DESKTOP_QUERY);
  query.addEventListener?.("change", onChange);
  return () => query.removeEventListener?.("change", onChange);
}

export function useDesktopLayout() {
  return useSyncExternalStore(
    subscribe,
    () => typeof window !== "undefined" && typeof window.matchMedia === "function" && window.matchMedia(DESKTOP_QUERY).matches,
    () => false,
  );
}

/** A short line read out by screen readers and shown for a few seconds («Μπήκε στην Ημ. 3»). */
export function useNotice(ms = 3200) {
  const [notice, setNotice] = useState<{ text: string; at: number } | null>(null);
  const timer = useRef<number | null>(null);
  useEffect(() => () => {
    if (timer.current) window.clearTimeout(timer.current);
  }, []);
  const say = useCallback(
    (text: string) => {
      if (timer.current) window.clearTimeout(timer.current);
      setNotice({ text, at: Date.now() });
      timer.current = window.setTimeout(() => setNotice(null), ms);
    },
    [ms],
  );
  return { notice: notice?.text ?? null, say };
}

/** «Δύναμη · ~50′»: the WOD's family and, when stated, its length. */
export function useWodFacts() {
  const t = useTranslations("Programmes.editor2");
  const labels = useWorkoutTypeLabels();
  return useCallback(
    (wod: LibraryWod) => [labels.family(wod.type), wod.minutes ? t("minutes", { minutes: wod.minutes }) : null].filter(Boolean).join(" · "),
    [labels, t],
  );
}

/** The family's colour mark next to a WOD. */
export function FamilyDot({ type, className = "h-2.5 w-2.5" }: { type: string | null | undefined; className?: string }) {
  return <i aria-hidden="true" className={`inline-block shrink-0 rounded-full ${className}`} style={{ background: type ? workoutTypeColor(type) : "var(--dim)" }} />;
}

/** A WOD in a list: colour, title and facts. */
export function WodLine({ wod, fallbackTitle }: { wod: LibraryWod | undefined; fallbackTitle: string }) {
  const facts = useWodFacts();
  return (
    <span className="flex min-w-0 flex-1 items-center gap-2.5">
      <FamilyDot type={wod?.type} />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
          {wod?.title ?? fallbackTitle}
        </span>
        {wod ? (
          <span className="block truncate text-xs" style={{ color: "var(--muted)" }}>
            {facts(wod)}
          </span>
        ) : null}
      </span>
    </span>
  );
}

/** «5 και 6»: weeks as a list in the reader's language. */
export function useWeekList() {
  return useCallback((weeks: number[], locale: string) => {
    try {
      return new Intl.ListFormat(locale, { style: "long", type: "conjunction" }).format(weeks.map(String));
    } catch {
      return weeks.join(", ");
    }
  }, []);
}
