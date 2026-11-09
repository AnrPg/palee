"use client";

import { useEffect, useReducer } from "react";
import { useFormatter, useTranslations } from "next-intl";

import { splitList } from "@/components/business-landing/BusinessVisuals";
import type { Audience } from "@/components/business-landing/content";
import { consoleReducer, CONSOLE_CAPACITY, initialConsole, toastAt } from "@/components/business-landing/console-state";

const TICK_MS = 650;

function prefersReducedMotion() {
  return typeof window !== "undefined" && typeof window.matchMedia === "function" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/**
 * The business hero's laptop (ADR-556): the staff console living a day on
 * its own. Seats fill, the waiting list opens when a class is full, takings
 * add up and notices slide in. Decoration: the hero's text says it all.
 */
export function BusinessConsole({ audience }: { audience: Audience }) {
  const t = useTranslations("BusinessLanding");
  const format = useFormatter();
  const [state, dispatch] = useReducer(consoleReducer, undefined, initialConsole);

  useEffect(() => {
    dispatch({ type: "reset" });
    if (prefersReducedMotion()) return;
    const timer = setInterval(() => dispatch({ type: "tick" }), TICK_MS);
    return () => clearInterval(timer);
  }, [audience]);

  const nav = splitList(t(`console.${audience}.nav`));
  const kpis = splitList(t(`console.${audience}.kpis`));
  const rows = splitList(t(`console.${audience}.rows`));
  const toasts = splitList(t(`console.${audience}.toasts`));
  const money = (euros: number) => format.number(euros, { style: "currency", currency: "EUR", maximumFractionDigits: 0 });
  const kpiValues = [String(state.bookings), String(state.checkIns), money(state.takings)];

  return (
    <div className="landing-bob relative w-full max-w-[35rem]" aria-hidden="true" data-testid="business-console">
      <div
        className="grid min-h-[20rem] grid-cols-1 overflow-hidden rounded-t-[1.1rem] text-[11px] sm:grid-cols-[6rem_1fr]"
        style={{ background: "var(--bg)", color: "var(--text)", border: "10px solid color-mix(in srgb, var(--deep-contrast) 18%, var(--deep))", borderBottomWidth: 14 }}
      >
        <div className="hidden content-start gap-1 p-2.5 sm:grid" style={{ background: "var(--panel)", borderInlineEnd: "1px solid var(--border)" }}>
          <b className="mb-1.5 truncate text-xs">{t(`console.${audience}.name`)}</b>
          {nav.map((item, index) => (
            <span
              key={item}
              className="truncate rounded-lg px-2 py-1"
              style={index === 0 ? { background: "var(--spark)", color: "var(--spark-contrast)", fontWeight: 700 } : { color: "var(--text-soft)" }}
            >
              {item}
            </span>
          ))}
        </div>
        <div className="flex min-w-0 flex-col gap-2 p-3">
          <b className="text-[13px]">{t("console.today")}</b>
          <div className="grid grid-cols-3 gap-1.5">
            {kpis.map((label, index) => (
              <span key={label} className="rounded-lg px-2 py-1.5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <b className="block text-[15px] tabular-nums">{kpiValues[index]}</b>
                <span className="block truncate text-[10px]" style={{ color: "var(--muted)" }}>{label}</span>
              </span>
            ))}
          </div>
          {rows.map((name, row) => {
            const capacity = CONSOLE_CAPACITY[row];
            const filled = state.seats[row];
            return (
              <div key={name} className="grid gap-1.5 rounded-lg px-2.5 py-2" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <span className="flex items-center justify-between gap-2 font-bold">
                  <span className="truncate">{name}</span>
                  <span className="flex items-center gap-1.5 tabular-nums">
                    {filled}/{capacity}
                    {filled === capacity ? (
                      <span className="rounded-full px-1.5 text-[10px] font-extrabold" style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}>
                        {t("console.waitlist")}
                      </span>
                    ) : null}
                  </span>
                </span>
                <span className="flex flex-wrap gap-[3px]">
                  {Array.from({ length: capacity }, (_, seat) => (
                    <span
                      key={seat}
                      className="landing-seat size-2.5 rounded-full"
                      data-on={seat < filled}
                      style={seat < filled ? { background: "var(--primary)" } : { background: "var(--panel-muted)", border: "1px solid var(--border)" }}
                    />
                  ))}
                </span>
              </div>
            );
          })}
          {/* Notices sit in their own strip under the classes, never on top of them. */}
          <div className="mt-auto grid min-h-[3.75rem] content-end justify-items-end gap-1.5">
            {state.toasts.map((toast) => (
              <span
                key={toast}
                className="landing-toast flex max-w-full items-center gap-2 rounded-lg px-2.5 py-1.5 font-semibold shadow-(--shadow-lg)"
                style={{ background: "var(--deep)", color: "var(--deep-contrast)" }}
              >
                <span className="shrink-0 font-black" style={{ color: "var(--spark)" }}>✓</span>
                <span className="truncate">{toastAt(toasts, toast)}</span>
              </span>
            ))}
          </div>
        </div>
      </div>
      <div className="-mx-7 h-3.5 rounded-b-[1.1rem]" style={{ background: "color-mix(in srgb, var(--deep-contrast) 18%, var(--deep))" }} />
    </div>
  );
}
