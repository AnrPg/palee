"use client";

import { useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import { BusinessVisual } from "@/components/business-landing/BusinessVisuals";
import { DAY, type Audience } from "@/components/business-landing/content";
import { Dialog } from "@/components/ui/Dialog";

/**
 * «See how it works» (ADR-556): one day at the business, hour by hour. As
 * the visitor scrolls, the step in view lights up, the line fills and, from
 * tablets up, the phone beside it changes screen. Phones show each step's
 * picture under its text instead.
 */
export function HowItWorks({ audience, onClose, onStart }: { audience: Audience; onClose: () => void; onStart: () => void }) {
  const t = useTranslations("BusinessLanding");
  const steps = DAY[audience];
  const scroller = useRef<HTMLDivElement>(null);
  const line = useRef<HTMLOListElement>(null);
  const [current, setCurrent] = useState(0);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const host = scroller.current;
    const track = line.current;
    if (!host || !track) return;
    const update = () => {
      const middle = host.getBoundingClientRect().top + host.clientHeight * 0.45;
      const items = Array.from(track.querySelectorAll<HTMLElement>("[data-step]"));
      let active = 0;
      items.forEach((item, index) => {
        if (item.getBoundingClientRect().top <= middle) active = index;
      });
      const box = track.getBoundingClientRect();
      setCurrent(active);
      setProgress(Math.max(0, Math.min(1, (middle - box.top) / Math.max(box.height, 1))));
    };
    update();
    host.addEventListener("scroll", update, { passive: true });
    return () => host.removeEventListener("scroll", update);
  }, [audience]);

  return (
    <Dialog
      onClose={onClose}
      ariaLabel={t("how.dialog")}
      variant="screen"
      size="full"
      bare
      panelClassName="sm:h-full"
      testId="business-how"
    >
      <header className="flex shrink-0 items-center justify-between gap-3 px-5 py-3.5 sm:px-6" style={{ borderBottom: "1px solid var(--border)" }}>
        <h2 className="text-lg font-black tracking-tight sm:text-xl">{t(`how.${audience}.title`)}</h2>
        <button
          type="button"
          onClick={onClose}
          aria-label={t("how.close")}
          className="grid size-11 shrink-0 place-items-center rounded-full text-xl font-bold"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
        >
          ×
        </button>
      </header>
      <div ref={scroller} className="min-h-0 flex-1 overflow-y-auto" style={{ background: "var(--bg)" }}>
        <div className="mx-auto grid max-w-6xl gap-10 px-5 pb-10 pt-8 sm:px-8 md:grid-cols-[minmax(0,1fr)_18rem] lg:grid-cols-[minmax(0,1fr)_22rem] lg:gap-14">
          <ol ref={line} className="relative grid">
            <span className="absolute start-[1.9rem] top-0 h-full w-[3px]" style={{ background: "var(--border)" }} aria-hidden="true" />
            <span
              className="absolute start-[1.9rem] top-0 w-[3px] transition-[height] duration-300"
              style={{ background: "var(--primary)", height: `${progress * 100}%` }}
              aria-hidden="true"
            />
            {steps.map((step, index) => (
              <li
                key={step.id}
                data-step
                data-on={index === current}
                className="landing-step relative grid content-start gap-2 pb-12 ps-20 md:min-h-[19rem]"
              >
                <span
                  className="landing-step-time absolute start-0 -top-1 grid h-9 w-16 place-items-center rounded-full text-sm font-black tabular-nums"
                  style={{ background: "var(--panel)", border: "2px solid var(--border)" }}
                >
                  {t(`how.${audience}.${step.id}.time`)}
                </span>
                <h3 className="text-2xl font-black tracking-tight lg:text-3xl">{t(`how.${audience}.${step.id}.title`)}</h3>
                <p className="max-w-[44ch]" style={{ color: "var(--text-soft)" }}>{t(`how.${audience}.${step.id}.body`)}</p>
                <div className="mt-3 grid max-w-sm md:hidden">
                  <BusinessVisual id={step.visual} />
                </div>
              </li>
            ))}
          </ol>
          <div className="sticky top-6 hidden self-start md:grid md:place-items-center" aria-hidden="true">
            <div className="relative h-[34rem] w-full max-w-[17rem] rounded-[2.75rem] p-3 shadow-(--shadow-lg) lg:h-[38rem] lg:max-w-[19rem]" style={{ background: "var(--deep)" }}>
              <div className="relative h-full overflow-hidden rounded-[2.1rem]" style={{ background: "var(--bg)", color: "var(--text)" }}>
                {steps.map((step, index) => (
                  <div key={step.id} className="landing-scene absolute inset-0 grid content-start gap-2.5 px-4 pb-4 pt-10" data-on={index === current}>
                    <span className="text-xs font-extrabold uppercase tracking-[0.2em]" style={{ color: "var(--primary)" }}>
                      {t(`how.${audience}.${step.id}.time`)}
                    </span>
                    <b className="text-base leading-snug">{t(`how.${audience}.${step.id}.title`)}</b>
                    <div className="mt-6 grid">
                      <BusinessVisual id={step.visual} />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
        <div className="flex justify-center px-5 pb-12">
          <button
            type="button"
            onClick={onStart}
            className="min-h-12 rounded-full px-7 text-base font-extrabold"
            style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
          >
            {t("hero.cta")}
          </button>
        </div>
      </div>
    </Dialog>
  );
}
