"use client";

import Link from "next/link";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";

import type { ProgrammeBuyerDay } from "@/api/programme-days";
import { Icon } from "@/components/box-page/Icon";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

import { canStart, dayWorkoutHref, focusDay, focusWeek, progressPercent, weekDays, type DaysView } from "./programme-day-model";
import { utcDay } from "./programme-grid";

type Action = "today" | "skip";

/**
 * «Η μέρα μου» in a bought programme (board 3κ/3μ A, ADR-540). Phone: the
 * progress, the «Έμεινε πίσω» card with «Κάν' τη σήμερα» / «Παράλειψη», the
 * week's day strip, the chosen day with «Ξεκίνα», the week's list. Desktop:
 * the day on the left, the week as a 7-column board on the right.
 */
export function ProgrammeDayBoard({
  view,
  pending,
  error,
  onAction,
}: {
  view: DaysView;
  pending: boolean;
  error: string | null;
  onAction: (action: Action, day: number) => void;
}) {
  const t = useTranslations("Programmes");
  const [pick, setPick] = useState<{ week: number; day: number | null } | null>(null);

  if (view.days.length === 0) {
    return <p className="text-sm" style={{ color: "var(--dim)" }} data-testid="programme-days-empty">{t("buyer2.noDays")}</p>;
  }

  const current = focusWeek(view);
  const week = Math.min(Math.max(pick?.week ?? current, 1), Math.max(view.weeks, 1));
  const days = weekDays(view, week);
  const selected = days.find((day) => day.day === pick?.day) ?? days.find((day) => day.day === focusDay(days)) ?? days[0];
  const percent = progressPercent(view.progress);
  const choose = (day: ProgrammeBuyerDay) => setPick({ week, day: day.day });
  const goWeek = (next: number) => setPick({ week: next, day: null });

  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,24rem)_minmax(0,1fr)] lg:items-start lg:gap-6" data-testid="programme-days">
      <div className="lg:col-span-2">
        <div className="flex items-baseline gap-3 text-sm">
          <span className="flex-1" style={{ color: "var(--text-soft)" }}>{t("buyer2.weekOf", { week: current, weeks: Math.max(view.weeks, current) })}</span>
          <b className="tabular-nums" style={{ color: "var(--text)" }} data-testid="programme-progress">
            {t("buyer2.doneOf", { done: view.progress.done, total: view.progress.total })}
          </b>
        </div>
        <div
          className="mt-1.5 h-2 overflow-hidden rounded-full"
          style={{ background: "var(--panel-muted)" }}
          role="progressbar"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={percent}
          aria-label={t("buyer2.doneOf", { done: view.progress.done, total: view.progress.total })}
        >
          <div className="h-full rounded-full" style={{ width: `${percent}%`, background: "var(--primary)" }} />
        </div>
      </div>

      {view.behind ? (
        <div className="lg:col-start-2 lg:row-start-3">
          <BehindCard behind={view.behind} pending={pending} error={error} onAction={onAction} />
        </div>
      ) : null}

      <div className="grid grid-cols-7 gap-1.5 lg:hidden" role="group" aria-label={t("buyer2.daysAria")} data-testid="programme-day-strip">
        {days.map((day) => (
          <StripDay key={day.day} day={day} selected={day.day === selected.day} onClick={() => choose(day)} />
        ))}
      </div>

      <div className="lg:col-start-1 lg:row-span-2 lg:row-start-2">
        <DayCard day={selected} />
      </div>

      <section className="flex min-w-0 flex-col gap-2 lg:col-start-2 lg:row-start-2" data-testid="programme-week">
        <div className="flex items-center gap-1">
          <h2 className="flex-1 text-sm font-bold lg:text-base" style={{ color: "var(--text)" }}>
            {week === current ? t("buyer2.thisWeek") : t("buyer2.week", { week })}
          </h2>
          <WeekButton label={t("buyer2.prevWeek")} icon="chevron-left" disabled={week <= 1} onClick={() => goWeek(week - 1)} />
          <WeekButton label={t("buyer2.nextWeek")} icon="chevron-right" disabled={week >= view.weeks} onClick={() => goWeek(week + 1)} />
        </div>
        <ul className="flex flex-col gap-1.5 lg:grid lg:grid-cols-7 lg:gap-2">
          {days.map((day) => (
            <li key={day.day} className={day.status === "rest" ? "hidden lg:block" : undefined}>
              <WeekDay day={day} selected={day.day === selected.day} onClick={() => choose(day)} />
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}

function WeekButton({ label, icon, disabled, onClick }: { label: string; icon: "chevron-left" | "chevron-right"; disabled: boolean; onClick: () => void }) {
  return (
    <button type="button" aria-label={label} disabled={disabled} onClick={onClick} className="grid h-11 w-11 place-items-center rounded-full disabled:opacity-30" style={{ color: "var(--text-soft)" }}>
      <span className="rtl:rotate-180"><Icon name={icon} size={18} /></span>
    </button>
  );
}

function useWeekdayName() {
  const locale = useLocale();
  return (iso: string) => (iso ? new Intl.DateTimeFormat(locale, { weekday: "long", timeZone: "UTC" }).format(utcDay(iso)) : "");
}

function BehindCard({
  behind,
  pending,
  error,
  onAction,
}: {
  behind: NonNullable<DaysView["behind"]>;
  pending: boolean;
  error: string | null;
  onAction: (action: Action, day: number) => void;
}) {
  const t = useTranslations("Programmes");
  const weekdayName = useWeekdayName();
  const name = weekdayName(behind.date);
  const day = behind.weekday + 1;
  return (
    <div
      className="flex flex-col gap-2 rounded-2xl p-4"
      style={{ background: "color-mix(in srgb, var(--warning) 12%, var(--panel))", border: "1px solid color-mix(in srgb, var(--warning) 45%, transparent)" }}
      data-testid="programme-behind"
    >
      <b className="text-sm" style={{ color: "var(--text)" }}>{name ? t("buyer2.behindTitle", { day, weekday: name }) : t("buyer2.behindTitleShort", { day })}</b>
      <span className="text-sm" style={{ color: "var(--text-soft)" }}>{behind.can_do_today ? t("buyer2.behindText") : t("buyer2.behindNoRoom")}</span>
      <div className="flex gap-2">
        {behind.can_do_today ? (
          <button
            type="button"
            disabled={pending}
            onClick={() => onAction("today", behind.day)}
            className="min-h-11 flex-1 rounded-2xl px-3 text-sm font-bold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("buyer2.doToday")}
          </button>
        ) : null}
        {behind.can_skip ? (
          <button
            type="button"
            disabled={pending}
            onClick={() => onAction("skip", behind.day)}
            className="min-h-11 flex-1 rounded-2xl px-3 text-sm font-bold disabled:opacity-50"
            style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
          >
            {t("buyer2.skip")}
          </button>
        ) : null}
      </div>
      {error ? <ErrorNotice variant="field">{error}</ErrorNotice> : null}
    </div>
  );
}

const STATUS_TONE: Record<ProgrammeBuyerDay["status"], string> = {
  done: "var(--success)",
  skipped: "var(--dim)",
  behind: "var(--warning)",
  today: "var(--primary-strong)",
  upcoming: "var(--text)",
  rest: "var(--dim)",
};

function StripDay({ day, selected, onClick }: { day: ProgrammeBuyerDay; selected: boolean; onClick: () => void }) {
  const t = useTranslations("Programmes");
  const today = day.status === "today";
  return (
    <button
      type="button"
      aria-pressed={selected}
      aria-label={`${t("dayShort", { day: day.weekday + 1 })} · ${t(`buyer2.status.${day.status}`)}`}
      onClick={onClick}
      className="relative flex min-h-11 flex-col items-center justify-center rounded-xl text-sm font-bold tabular-nums"
      style={{
        background: today ? "var(--primary)" : selected ? "var(--panel-raised)" : "var(--panel)",
        color: today ? "var(--primary-contrast)" : STATUS_TONE[day.status],
        border: `${selected ? 2 : 1}px solid ${selected ? "var(--primary)" : "var(--border)"}`,
        textDecoration: day.status === "skipped" ? "line-through" : undefined,
      }}
    >
      {day.status === "done" ? <Icon name="check" size={16} /> : day.weekday + 1}
      {day.status === "behind" ? <span aria-hidden="true" className="absolute bottom-1 h-1.5 w-1.5 rounded-full" style={{ background: "var(--warning)" }} /> : null}
    </button>
  );
}

function StatusPill({ status }: { status: ProgrammeBuyerDay["status"] }) {
  const t = useTranslations("Programmes");
  if (status === "upcoming" || status === "rest") return null;
  const tone = STATUS_TONE[status];
  return (
    <span className="inline-flex shrink-0 items-center gap-1 self-start rounded-full px-2 py-0.5 text-xs font-bold" style={{ background: `color-mix(in srgb, ${tone} 14%, transparent)`, color: tone }}>
      {status === "done" ? <Icon name="check" size={12} /> : null}
      {t(`buyer2.pill.${status}`)}
    </span>
  );
}

function dayTitle(day: ProgrammeBuyerDay, fallback: string) {
  return day.workouts.map((workout) => workout.title ?? fallback).join(" · ");
}

function WeekDay({ day, selected, onClick }: { day: ProgrammeBuyerDay; selected: boolean; onClick: () => void }) {
  const t = useTranslations("Programmes");
  const rest = day.status === "rest";
  return (
    <button
      type="button"
      aria-pressed={selected}
      onClick={onClick}
      className="flex min-h-11 w-full items-center gap-3 rounded-xl px-3 py-2 text-start text-sm lg:h-full lg:min-h-28 lg:flex-col lg:items-start lg:gap-1.5 lg:p-2.5"
      style={{
        background: day.status === "today" ? "color-mix(in srgb, var(--primary) 10%, var(--panel))" : rest ? "var(--panel-muted)" : "var(--panel)",
        border: `1px solid ${selected ? "var(--primary)" : "var(--border)"}`,
      }}
      data-testid={`programme-day-${day.day}`}
    >
      <span className="w-12 shrink-0 text-xs font-bold lg:w-auto" style={{ color: "var(--dim)" }}>{t("dayShort", { day: day.weekday + 1 })}</span>
      <span className="min-w-0 flex-1 break-words font-semibold lg:flex-none" style={{ color: rest ? "var(--dim)" : "var(--text)" }}>
        {rest ? t("rest") : dayTitle(day, t("unknownWod"))}
      </span>
      <StatusPill status={day.status} />
    </button>
  );
}

function DayCard({ day }: { day: ProgrammeBuyerDay }) {
  const t = useTranslations("Programmes");
  const locale = useLocale();
  const where = t("buyer2.weekDay", { week: day.week, day: day.weekday + 1 });
  const href = dayWorkoutHref(day);
  const date = day.date ? new Intl.DateTimeFormat(locale, { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }).format(utcDay(day.date)) : null;

  if (day.status === "rest") {
    return (
      <article className="flex flex-col gap-1 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="programme-day-card">
        <span className="text-xs" style={{ color: "var(--muted)" }}>{[where, date].filter(Boolean).join(" · ")}</span>
        <h2 className="text-lg font-extrabold" style={{ color: "var(--dim)" }}>{t("rest")}</h2>
      </article>
    );
  }

  return (
    <article
      className="flex flex-col gap-3 rounded-3xl p-5 lg:p-6"
      style={{ background: "var(--panel)", border: `1px solid ${day.status === "today" ? "var(--primary)" : "var(--border)"}` }}
      data-testid="programme-day-card"
    >
      <span className="text-xs font-semibold" style={{ color: "var(--muted)" }}>
        {[t(`buyer2.status.${day.status}`), where, day.status === "upcoming" ? date : null].filter(Boolean).join(" · ")}
      </span>
      <div className="flex flex-col gap-2">
        {day.workouts.map((workout) => (
          <div key={workout.workout_id} className="flex flex-col gap-0.5">
            <h2 className="break-words text-lg font-extrabold lg:text-xl" style={{ color: "var(--text)" }}>{workout.title ?? t("unknownWod")}</h2>
            {workout.summary ? <p className="whitespace-pre-line text-sm" style={{ color: "var(--text-soft)" }}>{workout.summary}</p> : null}
          </div>
        ))}
      </div>
      {canStart(day) && href ? (
        <Link href={href} className="flex min-h-12 items-center justify-center rounded-2xl px-4 text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} data-testid="programme-day-start">
          {t("buyer2.start")}
        </Link>
      ) : day.status === "done" && href ? (
        <Link href={href} className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold" style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}>
          {t("buyer2.seeLog")}
        </Link>
      ) : null}
    </article>
  );
}
