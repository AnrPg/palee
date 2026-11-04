"use client";

import { useEffect, useMemo, useRef, useState, type CSSProperties } from "react";

import { classTypes, countdown, nextClass, scheduleDays, typeColor } from "../site-data";
import { useClock, useSite, useSiteText } from "../site-context";

/**
 * «Ωρολόγιο πρόγραμμα» (ADR-530): day chips, type filters and one pane per
 * day that swipes sideways (the chips are the buttons for the same thing).
 * «Δοκίμασε» puts the class in the trial form; past classes fade.
 */
export function Schedule() {
  const { site, locale, on, act, calm } = useSite();
  const { t } = useSiteText();
  const now = useClock(60_000);
  const days = useMemo(() => scheduleDays(site.timetable, site.time_zone, locale, site.class_type_names, now), [site, locale, now]);
  const types = useMemo(() => classTypes(site.timetable), [site.timetable]);
  const [day, setDay] = useState(0);
  const [type, setType] = useState<string | null>(null);
  const panes = useRef<HTMLDivElement>(null);
  const settle = useRef<number | undefined>(undefined);

  useEffect(() => () => window.clearTimeout(settle.current), []);

  if (days.length === 0) return null;

  function pick(index: number) {
    setDay(index);
    const element = panes.current;
    if (element && typeof element.scrollTo === "function") element.scrollTo({ left: index * element.clientWidth * (document.dir === "rtl" ? -1 : 1), behavior: calm ? "auto" : "smooth" });
  }

  function scrolled() {
    window.clearTimeout(settle.current);
    settle.current = window.setTimeout(() => {
      const element = panes.current;
      if (!element || !element.clientWidth) return;
      const index = Math.round(Math.abs(element.scrollLeft) / element.clientWidth);
      if (index !== day && index >= 0 && index < days.length) setDay(index);
    }, 80);
  }

  const label = (index: number) => (index === 0 && now !== null ? t("schedule.today") : days[index]!.weekday);
  const trial = on("trial_form");

  return (
    <div className="sched" data-testid="site-schedule">
      <div className="days" role="tablist" aria-label={t("schedule.day")}>
        {days.map((entry, index) => (
          <button
            key={entry.day}
            type="button"
            role="tab"
            id={`bw-day-${entry.day}`}
            aria-selected={index === day}
            aria-controls={`bw-pane-${entry.day}`}
            onClick={() => pick(index)}
          >
            <small>{label(index)}</small>
            <b>{entry.date}</b>
          </button>
        ))}
      </div>
      {types.length > 1 ? (
        <div className="types" role="group" aria-label={t("schedule.type")}>
          {types.map((name) => (
            <button key={name} type="button" aria-pressed={type === name} onClick={() => setType(type === name ? null : name)}>
              {site.class_type_names[name] ?? name}
            </button>
          ))}
        </div>
      ) : null}
      <div className="panes" ref={panes} tabIndex={0} aria-label={t("schedule.panes")} onScroll={scrolled}>
        {days.map((entry, index) => {
          const shown = entry.entries.filter((item) => !type || item.type === type);
          return (
            <div key={entry.day} className="pane" id={`bw-pane-${entry.day}`} role="tabpanel" aria-labelledby={`bw-day-${entry.day}`}>
              <h3>
                {label(index)} {entry.date}
              </h3>
              {shown.length === 0 ? <p className="muted">{type ? t("schedule.emptyType") : t("schedule.empty")}</p> : null}
              {shown.map((item) => {
                const past = now !== null && item.startsAt < now;
                return (
                  <div key={item.id} className={`cls ${past ? "past" : ""}`}>
                    <span className="t">{item.time}</span>
                    <span>
                      <span className="n">
                        <span className="tag" style={{ "--tc": typeColor(Math.max(0, types.indexOf(item.type))) } as CSSProperties} aria-hidden="true" />
                        {item.name}
                      </span>
                      <br />
                      <span className="d">{t("schedule.minutes", { count: item.minutes })}</span>
                    </span>
                    {past ? (
                      <span className="d">{t("schedule.done")}</span>
                    ) : trial ? (
                      <button
                        type="button"
                        aria-label={t("schedule.tryAria", { name: item.name, day: entry.weekday, time: item.time })}
                        onClick={() => act(`${entry.weekday} ${entry.date} ${item.time} · ${item.name}`, "trial")}
                      >
                        {t("schedule.try")}
                      </button>
                    ) : (
                      <span />
                    )}
                  </div>
                );
              })}
            </div>
          );
        })}
      </div>
    </div>
  );
}

/**
 * «Επόμενο τμήμα»: the class and a countdown that ticks every second (every
 * minute in calm mode). The server renders the first class without the
 * countdown; the browser fills it in.
 */
export function useNextClass() {
  const { site, calm, locale } = useSite();
  const { t } = useSiteText();
  const now = useClock(calm ? 60_000 : 1000);
  const next = nextClass(site.timetable, site.time_zone, now);
  if (!next) return null;
  const name = site.class_type_names[next.name] ?? next.name;
  const weekday = new Intl.DateTimeFormat(locale, { weekday: "short", timeZone: "UTC" }).format(new Date(Date.UTC(2024, 0, next.weekday)));
  const when = t("next.when", { day: next.dayOffset === 0 ? "today" : next.dayOffset === 1 ? "tomorrow" : "other", time: next.time, weekday });
  let counter = "";
  if (now !== null) {
    const left = countdown(next.inSeconds);
    counter = left.kind === "days" ? t("next.inDays", { count: left.days }) : calm ? left.text.slice(0, 5) : left.text;
  }
  return { ...next, name, when, counter };
}
