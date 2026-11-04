"use client";

import { useTranslations } from "next-intl";
import { useEffect, useMemo, useRef, useState } from "react";

import type { ProgrammeDay } from "@/api/programmes";
import { inputClass, inputStyle } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";
import { DAYS_PER_WEEK, MAX_WEEKS, MAX_WODS_PER_DAY } from "@/components/programmes/programme-grid";

import { FamilyDot, WodLine, useWodFacts } from "./editor-ui";
import { addWeek, filterLibrary, placeWorkout, recentWorkouts, restDays, setDay, trainingDays, workoutsOn, type LibraryWod } from "./programme-editor-model";
import { useWeekActions, type WeeksChange } from "./WeekActions";

/**
 * Board 1κ A: one week at a time. The weeks sit in a strip (an empty week
 * has an orange dot), the days are tall rows, and tapping a day opens the
 * WOD library in a sheet near the thumb. The week's actions are under «⋯».
 */
export function WeeksPhone({
  days,
  weeks,
  week,
  onWeek,
  library,
  loading,
  onChange,
  say,
}: {
  days: ProgrammeDay[];
  weeks: number;
  week: number;
  onWeek: (week: number) => void;
  library: LibraryWod[];
  loading: boolean;
  onChange: (change: WeeksChange) => void;
  say: (text: string) => void;
}) {
  const t = useTranslations("Programmes.editor2");
  const tp = useTranslations("Programmes");
  const facts = useWodFacts();
  const [day, setDayOpen] = useState<number | null>(null);
  const [actionsOpen, setActionsOpen] = useState(false);
  const byId = useMemo(() => new Map(library.map((wod) => [wod.id, wod])), [library]);
  const actions = useWeekActions({ days, weeks, onChange, onShowWeek: onWeek, say });
  const shown = Math.min(week, weeks - 1);
  const training = trainingDays(days, shown);

  return (
    <div className="flex flex-col gap-3" data-testid="programme-weeks-phone">
      <WeekStrip days={days} weeks={weeks} week={shown} onWeek={onWeek} onAdd={() => {
        onChange({ weeks: addWeek(weeks) });
        onWeek(weeks);
      }} />

      <div className="flex items-center gap-3">
        <div className="min-w-0 flex-1">
          <h2 className="text-base font-semibold" style={{ color: "var(--text)" }}>{t("weekTitle", { week: shown + 1 })}</h2>
          <p className="text-xs" style={{ color: "var(--muted)" }} data-testid="programme-week-summary">
            {training > 0 ? t("weekSummary", { training, rest: DAYS_PER_WEEK - training }) : t("emptyWeek")}
          </p>
        </div>
        <button
          type="button"
          onClick={() => setActionsOpen(true)}
          aria-label={t("weekActions", { week: shown + 1 })}
          className="grid h-11 w-11 place-items-center rounded-full text-lg"
          style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
          data-testid="programme-week-actions"
        >
          <span aria-hidden="true">⋯</span>
        </button>
      </div>

      <ol className="flex flex-col gap-2">
        {Array.from({ length: DAYS_PER_WEEK }, (_, slot) => {
          const index = shown * DAYS_PER_WEEK + slot;
          const ids = workoutsOn(days, index);
          const first = byId.get(ids[0] ?? "");
          return (
            <li key={index}>
              <button
                type="button"
                onClick={() => setDayOpen(index)}
                className="flex min-h-14 w-full items-center gap-3 rounded-2xl px-3 py-2 text-start"
                style={{
                  background: ids.length ? "var(--panel)" : "var(--panel-muted)",
                  border: ids.length ? "1px solid var(--border)" : "1px dashed var(--border)",
                }}
                data-testid={`programme-day-${index}`}
              >
                <span className="flex w-14 shrink-0 items-center gap-1.5 text-xs font-semibold" style={{ color: "var(--muted)" }}>
                  {ids.length ? <FamilyDot type={first?.type} className="h-2 w-2" /> : null}
                  {tp("dayShort", { day: slot + 1 })}
                </span>
                {ids.length ? (
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                      {ids.map((id) => byId.get(id)?.title ?? tp("unknownWod")).join(" + ")}
                    </span>
                    {first ? <span className="block truncate text-xs" style={{ color: "var(--muted)" }}>{facts(first)}</span> : null}
                  </span>
                ) : (
                  <>
                    <span className="min-w-0 flex-1 text-sm" style={{ color: "var(--dim)" }}>{tp("rest")}</span>
                    <span className="text-xs font-semibold" style={{ color: "var(--primary)" }}>{tp("addWod")}</span>
                  </>
                )}
              </button>
            </li>
          );
        })}
      </ol>

      {actionsOpen ? (
        <Dialog onClose={() => setActionsOpen(false)} title={t("weekTitle", { week: shown + 1 })} size="sm" testId="programme-week-sheet">
          <div className="flex flex-col gap-1">
            <SheetAction
              label={t("copyNext")}
              hint={t("copyNextHint")}
              testId="programme-copy-next"
              disabled={shown + 1 >= MAX_WEEKS}
              onClick={() => {
                setActionsOpen(false);
                actions.copyNext(shown);
              }}
            />
            {weeks > 1 ? (
              <SheetAction label={t("copyTo")} hint={t("copyToHint")} onClick={() => {
                setActionsOpen(false);
                actions.copyTo(shown);
              }} />
            ) : null}
            {actions.canMove ? (
              <SheetAction label={t("reorder")} onClick={() => {
                setActionsOpen(false);
                actions.move(shown);
              }} />
            ) : null}
            {actions.canDelete ? (
              <SheetAction label={t("deleteWeek")} tone="danger" testId="programme-delete-week" onClick={() => {
                setActionsOpen(false);
                actions.remove(shown);
              }} />
            ) : null}
          </div>
        </Dialog>
      ) : null}

      {day !== null ? (
        <DaySheet
          day={day}
          days={days}
          library={library}
          byId={byId}
          loading={loading}
          onClose={() => setDayOpen(null)}
          onPick={(workoutId) => {
            const result = placeWorkout(days, [day], workoutId);
            onChange({ days: result.days });
            setDayOpen(null);
            say(t("placedOn", { day: (day % DAYS_PER_WEEK) + 1 }));
          }}
          onRemove={(workoutId) => onChange({ days: setDay(days, day, workoutsOn(days, day).filter((id) => id !== workoutId)) })}
          onRest={() => {
            onChange({ days: restDays(days, [day]) });
            setDayOpen(null);
          }}
        />
      ) : null}
      {actions.dialogs}
    </div>
  );
}

function WeekStrip({ days, weeks, week, onWeek, onAdd }: { days: ProgrammeDay[]; weeks: number; week: number; onWeek: (week: number) => void; onAdd: () => void }) {
  const t = useTranslations("Programmes.editor2");
  const tp = useTranslations("Programmes");
  const active = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    active.current?.scrollIntoView?.({ block: "nearest", inline: "nearest" });
  }, [week]);
  return (
    // The strip fades at its end so a longer programme shows it scrolls (board tip «η οριζόντια κύλιση πρέπει να φαίνεται»).
    <nav aria-label={t("weeksStrip")} className="-mx-4 overflow-x-auto px-4 [mask-image:linear-gradient(to_right,black_85%,transparent)]">
      <ul className="flex w-max gap-2 pe-8">
        {Array.from({ length: weeks }, (_, index) => {
          const empty = trainingDays(days, index) === 0;
          const on = index === week;
          return (
            <li key={index}>
              <button
                ref={on ? active : undefined}
                type="button"
                onClick={() => onWeek(index)}
                aria-current={on ? "true" : undefined}
                className="flex min-h-11 items-center gap-1.5 rounded-full px-4 text-sm font-semibold"
                style={{
                  background: on ? "var(--primary)" : "var(--panel-muted)",
                  color: on ? "var(--primary-contrast)" : "var(--text-soft)",
                  border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`,
                }}
                data-testid={`programme-week-chip-${index}`}
              >
                {tp("weekShort", { week: index + 1 })}
                {empty ? (
                  <>
                    <i aria-hidden="true" className="inline-block h-2 w-2 rounded-full" style={{ background: "var(--warning)" }} />
                    <span className="sr-only">{t("emptyWeekShort")}</span>
                  </>
                ) : null}
              </button>
            </li>
          );
        })}
        {weeks < MAX_WEEKS ? (
          <li>
            <button
              type="button"
              onClick={onAdd}
              className="min-h-11 rounded-full px-4 text-sm font-semibold"
              style={{ border: "1px dashed var(--border)", color: "var(--primary)" }}
              data-testid="programme-add-week"
            >
              {tp("addWeek")}
            </button>
          </li>
        ) : null}
      </ul>
    </nav>
  );
}

function SheetAction({
  label,
  hint,
  tone,
  disabled,
  testId,
  onClick,
}: {
  label: string;
  hint?: string;
  tone?: "danger";
  disabled?: boolean;
  testId?: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="flex min-h-12 w-full flex-col justify-center rounded-xl px-3 py-2 text-start disabled:opacity-50"
      style={{ color: tone === "danger" ? "var(--danger)" : "var(--text)" }}
      data-testid={testId}
    >
      <span className="text-sm font-semibold">{label}</span>
      {hint ? <span className="text-xs" style={{ color: "var(--muted)" }}>{hint}</span> : null}
    </button>
  );
}

function DaySheet({
  day,
  days,
  library,
  byId,
  loading,
  onClose,
  onPick,
  onRemove,
  onRest,
}: {
  day: number;
  days: ProgrammeDay[];
  library: LibraryWod[];
  byId: Map<string, LibraryWod>;
  loading: boolean;
  onClose: () => void;
  onPick: (workoutId: string) => void;
  onRemove: (workoutId: string) => void;
  onRest: () => void;
}) {
  const t = useTranslations("Programmes.editor2");
  const tp = useTranslations("Programmes");
  const [query, setQuery] = useState("");
  const current = workoutsOn(days, day);
  const full = current.length >= MAX_WODS_PER_DAY;
  const recent = recentWorkouts(days)
    .filter((id) => !current.includes(id))
    .map((id) => byId.get(id))
    .filter((wod): wod is LibraryWod => Boolean(wod));
  const searching = query.trim() !== "";
  const listedAsRecent = new Set(searching ? [] : recent.map((wod) => wod.id));
  const results = filterLibrary(library, query, null)
    .filter((wod) => !current.includes(wod.id) && !listedAsRecent.has(wod.id))
    .slice(0, 50);

  return (
    <Dialog
      onClose={onClose}
      title={t("dayTitle", { week: Math.floor(day / DAYS_PER_WEEK) + 1, day: (day % DAYS_PER_WEEK) + 1 })}
      size="md"
      testId="programme-day-sheet"
    >
      <div className="flex flex-col gap-3">
        {current.length ? (
          <section aria-label={t("onThisDay")}>
            <h3 className="mb-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>{t("onThisDay")}</h3>
            <ul className="flex flex-col gap-1">
              {current.map((id) => (
                <li key={id} className="flex min-h-11 items-center gap-2 rounded-xl px-2" style={{ background: "var(--panel-muted)" }}>
                  <WodLine wod={byId.get(id)} fallbackTitle={tp("unknownWod")} />
                  <button
                    type="button"
                    onClick={() => onRemove(id)}
                    aria-label={tp("removeWod", { title: byId.get(id)?.title ?? tp("unknownWod") })}
                    className="grid h-11 w-11 place-items-center rounded-full"
                    style={{ color: "var(--muted)" }}
                  >
                    <span aria-hidden="true">×</span>
                  </button>
                </li>
              ))}
            </ul>
          </section>
        ) : null}

        {full ? (
          <p className="text-xs" style={{ color: "var(--muted)" }}>{t("dayIsFull")}</p>
        ) : (
          <>
            <input
              className={inputClass}
              style={inputStyle}
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder={t("searchLibrary")}
              aria-label={t("searchLibrary")}
              data-testid="programme-library-search"
            />
            {loading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{tp("loading")}</p> : null}
            {!searching && recent.length ? <WodList title={t("recent")} wods={recent} onPick={onPick} /> : null}
            {!loading ? (
              results.length ? (
                <WodList title={searching ? undefined : t("allWods")} wods={results} onPick={onPick} />
              ) : (
                <p className="text-sm" style={{ color: "var(--dim)" }}>{library.length ? tp("noWods") : t("libraryEmpty")}</p>
              )
            ) : null}
          </>
        )}

        {current.length ? (
          <button
            type="button"
            onClick={onRest}
            className="min-h-12 rounded-xl px-3 text-start text-sm font-semibold"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            data-testid="programme-day-rest"
          >
            {t("restThisDay")}
          </button>
        ) : null}
      </div>
    </Dialog>
  );
}

function WodList({ title, wods, onPick }: { title?: string; wods: LibraryWod[]; onPick: (id: string) => void }) {
  const tp = useTranslations("Programmes");
  return (
    <section aria-label={title}>
      {title ? <h3 className="mb-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>{title}</h3> : null}
      <ul className="flex flex-col gap-1">
        {wods.map((wod) => (
          <li key={wod.id}>
            <button
              type="button"
              onClick={() => onPick(wod.id)}
              className="flex min-h-12 w-full items-center rounded-xl px-2 text-start"
              style={{ border: "1px solid var(--border)" }}
              data-testid={`programme-pick-${wod.id}`}
            >
              <WodLine wod={wod} fallbackTitle={tp("unknownWod")} />
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}
