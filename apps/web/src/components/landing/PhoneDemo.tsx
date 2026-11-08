"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";

import { JournalVisual, PartnerVisual, PostVisual, ProgressVisual } from "@/components/landing/LandingVisuals";

const SCREENS = ["feed", "partners", "journal", "week"] as const;
type Screen = (typeof SCREENS)[number];
const TAB_FOR: Record<Screen, "feed" | "box" | "journal" | "messages" | "me"> = {
  feed: "feed",
  partners: "feed",
  journal: "journal",
  week: "me",
};
const SCREEN_MS = 3400;

function useReducedMotion() {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    if (typeof window.matchMedia !== "function") return;
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduced(query.matches);
    update();
    query.addEventListener?.("change", update);
    return () => query.removeEventListener?.("change", update);
  }, []);
  return reduced;
}

function WeekScreen() {
  const t = useTranslations("Landing");
  const rows = [
    [t("demo.weekWorkouts"), t("demo.weekStreak")],
    [t("demo.weekPr"), t("demo.weekPrMeta")],
    [t("demo.weekInsight"), t("demo.weekInsightMeta")],
  ];
  return (
    <div className="grid grid-cols-[minmax(0,1fr)] gap-2">
      <p className="text-base font-black">{t("demo.weekTitle")}</p>
      {rows.map(([title, meta]) => (
        <div key={title} className="rounded-xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-sm font-bold">{title}</p>
          <p className="text-xs" style={{ color: "var(--text-soft)" }}>{meta}</p>
        </div>
      ))}
    </div>
  );
}

/**
 * Tablets and up (ADR-555): a phone that plays the app on its own (Feed,
 * Συναθλητές, Journal, your week). Decoration only: the text beside it says
 * the same, so screen readers skip it. Reduced motion keeps the first screen.
 */
export function PhoneDemo() {
  const t = useTranslations("Landing");
  const reduced = useReducedMotion();
  const [index, setIndex] = useState(0);

  useEffect(() => {
    if (reduced) return;
    const timer = setInterval(() => setIndex((current) => (current + 1) % SCREENS.length), SCREEN_MS);
    return () => clearInterval(timer);
  }, [reduced]);

  const screen = SCREENS[reduced ? 0 : index];
  const tabs = ["feed", "box", "journal", "messages", "me"] as const;

  return (
    <div
      aria-hidden="true"
      className="relative w-[210px] shrink-0 rounded-[2.4rem] p-2.5 lg:w-[240px] 2xl:w-[280px]"
      style={{ background: "var(--deep)", border: "1px solid color-mix(in srgb, var(--deep-contrast) 22%, transparent)", boxShadow: "var(--shadow-lg)" }}
      data-testid="landing-phone"
    >
      <div className="flex aspect-[9/19] flex-col overflow-hidden rounded-[1.9rem]" style={{ background: "var(--bg)", color: "var(--text)" }}>
        <div className="mx-auto mt-2 h-4 w-20 rounded-full" style={{ background: "var(--deep)" }} />
        <div key={screen} className="landing-screen min-h-0 flex-1 overflow-hidden p-2.5" style={{ zoom: 0.8 }}>
          {screen === "feed" ? (
            <div className="grid grid-cols-[minmax(0,1fr)] gap-2">
              <PostVisual />
              <div className="rounded-xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <p className="text-sm font-bold">{t("demo.post2Name")}</p>
                <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("demo.post2Text")}</p>
              </div>
            </div>
          ) : screen === "partners" ? (
            <div className="grid grid-cols-[minmax(0,1fr)] gap-2">
              <p className="text-base font-black">{t("demo.partnersTitle")}</p>
              <PartnerVisual />
            </div>
          ) : screen === "journal" ? (
            <div className="grid grid-cols-[minmax(0,1fr)] gap-2">
              <JournalVisual />
              <ProgressVisual />
            </div>
          ) : (
            <WeekScreen />
          )}
        </div>
        <nav className="grid grid-cols-5 gap-0.5 px-1 py-2 text-center text-[0.6rem] font-semibold" style={{ borderTop: "1px solid var(--border)" }}>
          {tabs.map((tab) => (
            <span key={tab} className="truncate" style={{ color: TAB_FOR[screen] === tab ? "var(--primary)" : "var(--muted)" }}>
              {t(`demo.${tab}`)}
            </span>
          ))}
        </nav>
      </div>
    </div>
  );
}
