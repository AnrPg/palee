"use client";

import { useEffect, type RefObject } from "react";

/**
 * ADR-530: the website's motion, one effect per page. Transform and opacity
 * only, one passive rAF scroll handler, and reveals only for what is below
 * the first screen when the page opens (the first frame is complete at
 * rest). With «Λιγότερη κίνηση» or the visitor's reduced motion nothing
 * moves; hover effects need a mouse.
 *
 * Markup it reads:
 * - `data-rv="up|scale|left|lines"`: revealed when scrolled to (`--d` delays);
 * - `data-up="<number>"`: counts up when seen;
 * - `data-par="<factor>"`: parallax against its parent;
 * - `data-prog`: the scroll progress bar;
 * - `data-words`: words that light up one by one;
 * - `data-night`: the section that darkens the page (`.site.dk`);
 * - `.magnet`, `data-tilt`, `data-float-host`/`data-float`: hover effects.
 */
export function useSiteMotion({
  root,
  site,
  scroller,
  calm,
  locale,
  key,
}: {
  root: RefObject<HTMLElement | null>;
  site: RefObject<HTMLElement | null>;
  /** The preview's scrolling frame; the window otherwise. */
  scroller: RefObject<HTMLElement | null> | null;
  calm: boolean;
  locale: string;
  /** Re-runs on a page change. */
  key: string;
}) {
  useEffect(() => {
    const host = root.current;
    if (!host) return;
    const frame = scroller?.current ?? null;
    const reduced = typeof window.matchMedia === "function" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const still = calm || reduced;
    const cleanup: (() => void)[] = [];
    const all = <T extends Element = HTMLElement>(selector: string) => Array.from(host.querySelectorAll<T & Element>(selector)) as T[];
    const viewport = () => (frame ? frame.getBoundingClientRect() : { top: 0, bottom: window.innerHeight, height: window.innerHeight });
    const format = new Intl.NumberFormat(locale);

    const countUp = (element: HTMLElement) => {
      const target = Number(element.dataset.up);
      const text = element.firstChild;
      if (still || !Number.isFinite(target) || !(text instanceof Text)) return;
      const started = performance.now();
      const step = (time: number) => {
        const k = Math.min(1, (time - started) / 1000);
        text.nodeValue = format.format(Math.round(target * (1 - Math.pow(1 - k, 3))));
        if (k < 1) requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    };

    const words = all("[data-words]");
    if (still) {
      words.forEach((element) => element.classList.add("lit"));
    } else if (typeof IntersectionObserver === "function") {
      const fold = viewport().bottom - 10;
      const below = all("[data-rv]").filter((element) => element.getBoundingClientRect().top > fold);
      below.forEach((element) => element.classList.add(`pre-${element.dataset.rv}`));
      const reveal = new IntersectionObserver(
        (entries) =>
          entries.forEach((entry) => {
            if (!entry.isIntersecting) return;
            const element = entry.target as HTMLElement;
            element.classList.add("rv-done");
            requestAnimationFrame(() => element.classList.remove(`pre-${element.dataset.rv}`));
            [...(element.matches("[data-up]") ? [element] : []), ...Array.from(element.querySelectorAll<HTMLElement>("[data-up]"))].forEach(countUp);
            reveal.unobserve(element);
          }),
        { root: frame, threshold: 0.15 },
      );
      below.forEach((element) => reveal.observe(element));
      cleanup.push(() => reveal.disconnect());
      const counters = new IntersectionObserver(
        (entries) =>
          entries.forEach((entry) => {
            if (!entry.isIntersecting) return;
            countUp(entry.target as HTMLElement);
            counters.unobserve(entry.target);
          }),
        { root: frame, threshold: 0.5 },
      );
      all("[data-up]")
        .filter((element) => !element.closest("[data-rv]") && element.getBoundingClientRect().top > fold)
        .forEach((element) => counters.observe(element));
      cleanup.push(() => counters.disconnect());
    }

    // One passive scroll handler: transform and opacity only.
    const progress = all("[data-prog]");
    const parallax = all("[data-par]");
    const wordSpans = words.map((element) => Array.from(element.querySelectorAll<HTMLElement>("span")));
    const night = host.querySelector<HTMLElement>("[data-night]");
    let frameRequest = 0;
    const tick = () => {
      frameRequest = 0;
      const view = viewport();
      const middle = view.top + view.height / 2;
      if (progress.length) {
        const max = frame ? frame.scrollHeight - frame.clientHeight : document.documentElement.scrollHeight - window.innerHeight;
        const done = max > 0 ? (frame ? frame.scrollTop : window.scrollY) / max : 0;
        progress.forEach((bar) => (bar.style.transform = `scaleX(${Math.min(1, Math.max(0, done))})`));
      }
      if (still) return;
      for (const element of parallax) {
        const box = element.parentElement?.getBoundingClientRect();
        if (!box || box.bottom < view.top - 200 || box.top > view.bottom + 200) continue;
        element.style.transform = `translateY(${((box.top + box.height / 2 - middle) * -Number(element.dataset.par || 0)).toFixed(1)}px)`;
      }
      words.forEach((element, index) => {
        const box = element.getBoundingClientRect();
        const share = Math.min(1, Math.max(0, (view.bottom - box.top) / (box.height + view.height * 0.6)));
        const lit = Math.round(share * wordSpans[index]!.length * 1.25);
        wordSpans[index]!.forEach((span, position) => span.style.setProperty("--o", position < lit ? "1" : ".18"));
      });
      if (night) {
        const box = night.getBoundingClientRect();
        site.current?.classList.toggle("dk", box.top < middle && box.bottom > middle);
      }
    };
    const onScroll = () => {
      if (!frameRequest) frameRequest = requestAnimationFrame(tick);
    };
    const target: HTMLElement | Window = frame ?? window;
    target.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll, { passive: true });
    tick();
    cleanup.push(() => {
      target.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
      if (frameRequest) cancelAnimationFrame(frameRequest);
      site.current?.classList.remove("dk");
    });

    // Mouse only: magnetic buttons, tilting tiles, the coach beside the cursor.
    const hover = typeof window.matchMedia === "function" && window.matchMedia("(hover: hover) and (pointer: fine)").matches;
    if (hover && !still) {
      const listen = (element: Element, type: string, handler: (event: PointerEvent) => void) => {
        element.addEventListener(type, handler as EventListener);
        cleanup.push(() => element.removeEventListener(type, handler as EventListener));
      };
      all(".magnet").forEach((button) => {
        listen(button, "pointermove", (event) => {
          const box = button.getBoundingClientRect();
          button.style.transform = `translate(${((event.clientX - box.left - box.width / 2) * 0.2).toFixed(1)}px,${((event.clientY - box.top - box.height / 2) * 0.35).toFixed(1)}px)`;
        });
        listen(button, "pointerleave", () => (button.style.transform = ""));
      });
      all("[data-tilt]").forEach((tile) => {
        listen(tile, "pointermove", (event) => {
          const box = tile.getBoundingClientRect();
          const x = (event.clientX - box.left) / box.width - 0.5;
          const y = (event.clientY - box.top) / box.height - 0.5;
          tile.style.transform = `perspective(700px) rotateX(${(-y * 5).toFixed(2)}deg) rotateY(${(x * 6).toFixed(2)}deg)`;
        });
        listen(tile, "pointerleave", () => (tile.style.transform = ""));
      });
      all("[data-float-host]").forEach((section) => {
        const float = section.querySelector<HTMLElement>(".float");
        if (!float) return;
        listen(section, "pointermove", (event) => {
          const row = (event.target as Element).closest<HTMLElement>("[data-float]");
          if (!row) {
            float.classList.remove("on");
            return;
          }
          const box = section.getBoundingClientRect();
          const image = row.querySelector("img")?.getAttribute("src");
          const slot = float.querySelector("img");
          if (slot && image && slot.getAttribute("src") !== image) slot.setAttribute("src", image);
          float.classList.toggle("has-photo", Boolean(image));
          float.style.transform = "";
          float.style.left = `${event.clientX - box.left + 24}px`;
          float.style.top = `${event.clientY - box.top - 130}px`;
          float.classList.add("on");
        });
        listen(section, "pointerleave", () => float.classList.remove("on"));
      });
    }

    return () => cleanup.forEach((run) => run());
  }, [root, site, scroller, calm, locale, key]);
}
