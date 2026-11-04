"use client";

import { useTranslations } from "next-intl";
import { useEffect, useId, useMemo, useRef, useState, type DragEvent, type KeyboardEvent, type ReactNode } from "react";

import type { ProgrammeDay } from "@/api/programmes";
import { useWorkoutTypeLabels } from "@/components/workouts/WorkoutTypeSelect";
import { inputClass, inputStyle, secondaryButtonClass, secondaryButtonStyle } from "@/components/staff/staff-ui";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { DAYS_PER_WEEK, MAX_WEEKS } from "@/components/programmes/programme-grid";
import { workoutTypeColor } from "@/lib/theme";
import type { WorkoutTypeFamily } from "@/lib/workout-types";

import { WodLine } from "./editor-ui";
import {
  addWeek,
  dayRange,
  filterLibrary,
  libraryFamilies,
  moveCursor,
  pasteDay,
  placeWorkout,
  restDays,
  setDay,
  trainingDays,
  workoutsOn,
  type LibraryWod,
} from "./programme-editor-model";
import { useWeekActions, type WeeksChange } from "./WeekActions";

const WOD_MIME = "application/x-palee-wod";
/** The grid's shortcuts, announced on each day (aria-keyshortcuts). */
const KEY_SHORTCUTS = ["Control+C", "Control+V", "Meta+C", "Meta+V", "Delete", "Shift+ArrowRight"].join(" ");

/**
 * Board 1μ A: every week in a grid with the WOD library beside it. Drag a WOD
 * onto a day, or pick a day and then a WOD (the keyboard way: arrows to a
 * day, Enter, then Enter on a WOD). Shortcuts: ⌘/Ctrl C and V copy a day,
 * Shift selects several days, Del makes them rest days. A week's actions
 * show on its row.
 */
export function WeeksDesktop({
  days,
  weeks,
  library,
  loading,
  jump,
  banner,
  onChange,
  say,
}: {
  days: ProgrammeDay[];
  weeks: number;
  library: LibraryWod[];
  loading: boolean;
  /** Focus the first day of a week (from «Πήγαινε στο πρώτο»); `at` changes on each request. */
  jump: { week: number; at: number } | null;
  banner?: ReactNode;
  onChange: (change: WeeksChange) => void;
  say: (text: string) => void;
}) {
  const t = useTranslations("Programmes.editor2");
  const tp = useTranslations("Programmes");
  const byId = useMemo(() => new Map(library.map((wod) => [wod.id, wod])), [library]);
  const [cursor, setCursor] = useState(0);
  const [selection, setSelection] = useState<number[]>([]);
  const [anchor, setAnchor] = useState<number | null>(null);
  const [armed, setArmed] = useState<string | null>(null);
  const [copied, setCopied] = useState<string[] | null>(null);
  const [over, setOver] = useState<number | null>(null);
  const cells = useRef(new Map<number, HTMLDivElement>());
  const focusNext = useRef(false);
  const hintId = useId();
  const helpId = useId();
  const actions = useWeekActions({ days, weeks, onChange, say });
  const last = weeks * DAYS_PER_WEEK - 1;
  const current = Math.min(cursor, last);

  useEffect(() => {
    if (!focusNext.current) return;
    focusNext.current = false;
    cells.current.get(current)?.focus();
  }, [current]);

  useEffect(() => {
    if (!jump) return;
    const day = Math.min(jump.week, weeks - 1) * DAYS_PER_WEEK;
    queueMicrotask(() => {
      setCursor(day);
      setSelection([]);
      const cell = cells.current.get(day);
      cell?.scrollIntoView?.({ block: "center" });
      cell?.focus();
    });
    // Only a new request moves the focus, not later edits.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [jump?.at]);

  const selected = new Set(selection.filter((day) => day <= last));
  const targetsFor = (day: number) => (selected.has(day) && selected.size > 0 ? [...selected] : [day]);

  function place(targets: number[], workoutId: string) {
    const result = placeWorkout(days, targets, workoutId);
    onChange({ days: result.days });
    const title = byId.get(workoutId)?.title ?? tp("unknownWod");
    if (result.full > 0) say(t("daysFull", { count: result.full }));
    else if (targets.length === 1) say(t("placedOnWeekDay", { title, week: Math.floor(targets[0] / DAYS_PER_WEEK) + 1, day: (targets[0] % DAYS_PER_WEEK) + 1 }));
    else say(t("placedOnDays", { title, count: result.placed }));
  }

  function select(day: number, extend: boolean) {
    setCursor(day);
    if (extend) {
      const from = anchor ?? current;
      setAnchor(from);
      setSelection(dayRange(from, day));
      return;
    }
    setAnchor(day);
    setSelection(selected.size === 1 && selected.has(day) ? [] : [day]);
  }

  function activate(day: number, shift: boolean) {
    if (armed && !shift) {
      place(targetsFor(day), armed);
      setArmed(null);
      return;
    }
    select(day, shift);
  }

  function onGridKey(event: KeyboardEvent<HTMLDivElement>) {
    // Keys on the week rows' own buttons and menus are theirs.
    if ((event.target as HTMLElement).getAttribute("role") !== "gridcell") return;
    const mod = event.metaKey || event.ctrlKey;
    const key = event.key;
    if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End"].includes(key)) {
      event.preventDefault();
      const next = moveCursor(current, key, weeks);
      focusNext.current = true;
      if (event.shiftKey) select(next, true);
      else setCursor(next);
      return;
    }
    if (key === "Enter" || key === " ") {
      event.preventDefault();
      activate(current, event.shiftKey);
      return;
    }
    if (mod && key.toLowerCase() === "c") {
      event.preventDefault();
      setCopied(workoutsOn(days, current));
      say(t("copiedDay", { week: Math.floor(current / DAYS_PER_WEEK) + 1, day: (current % DAYS_PER_WEEK) + 1 }));
      return;
    }
    if (mod && key.toLowerCase() === "v") {
      event.preventDefault();
      if (!copied) return;
      const targets = selected.size ? [...selected] : [current];
      onChange({ days: pasteDay(days, copied, targets) });
      say(t("pasted", { count: targets.length }));
      return;
    }
    if (key === "Delete" || key === "Backspace") {
      event.preventDefault();
      const targets = selected.size ? [...selected] : [current];
      onChange({ days: restDays(days, targets) });
      say(t("rested", { count: targets.length }));
      return;
    }
    if (key === "Escape" && (selected.size || armed)) {
      event.preventDefault();
      setSelection([]);
      setArmed(null);
    }
  }

  function dropOn(day: number, event: DragEvent<HTMLDivElement>) {
    event.preventDefault();
    setOver(null);
    const workoutId = event.dataTransfer.getData(WOD_MIME) || event.dataTransfer.getData("text/plain");
    if (workoutId && byId.has(workoutId)) place(targetsFor(day), workoutId);
  }

  const single = selected.size === 1 ? [...selected][0] : null;

  return (
    <div className="grid min-w-0 grid-cols-[16rem_minmax(0,1fr)] gap-4" data-testid="programme-weeks-desktop">
      <Library
        library={library}
        loading={loading}
        armed={armed}
        onChoose={(id) => {
          if (selected.size) {
            place([...selected], id);
            return;
          }
          setArmed((currentArmed) => (currentArmed === id ? null : id));
          if (armed !== id) say(t("armed", { title: byId.get(id)?.title ?? tp("unknownWod") }));
        }}
      />

      <section className="flex min-w-0 flex-col gap-3">
        {banner}
        <div className="overflow-x-auto">
          <div
            role="grid"
            aria-label={t("gridLabel")}
            aria-multiselectable="true"
            aria-describedby={`${hintId} ${helpId}`}
            onKeyDown={onGridKey}
            className="grid min-w-[46rem] grid-cols-[8.5rem_repeat(7,minmax(0,1fr))] gap-1.5"
            data-testid="programme-grid"
          >
            <div role="row" className="contents">
              <span role="columnheader" className="sr-only">{t("weekColumn")}</span>
              {Array.from({ length: DAYS_PER_WEEK }, (_, slot) => (
                <span key={slot} role="columnheader" className="px-1 text-center text-xs font-semibold" style={{ color: "var(--dim)" }}>
                  {tp("dayShort", { day: slot + 1 })}
                </span>
              ))}
            </div>
            {Array.from({ length: weeks }, (_, week) => {
              const training = trainingDays(days, week);
              return (
                <div role="row" key={week} className="contents">
                  <div role="rowheader" className="group flex min-h-16 flex-col justify-center gap-0.5 rounded-xl px-2 py-1.5" style={{ background: "var(--panel-muted)" }}>
                    <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{tp("weekShort", { week: week + 1 })}</span>
                    <span className="text-xs" style={{ color: training ? "var(--muted)" : "var(--warning)" }}>
                      {training ? t("trainingCount", { count: training }) : t("emptyWeekShort")}
                    </span>
                    <span className="flex items-center gap-1 opacity-0 transition-opacity group-focus-within:opacity-100 group-hover:opacity-100">
                      {week + 1 < MAX_WEEKS ? (
                        <button
                          type="button"
                          onClick={() => actions.copyNext(week)}
                          aria-label={t("copyNextOf", { week: week + 1 })}
                          title={t("copyNextHint")}
                          className="rounded-lg px-1.5 py-0.5 text-xs font-semibold"
                          style={{ color: "var(--primary)" }}
                          data-testid={`programme-copy-next-${week}`}
                        >
                          {t("copyDown")}
                        </button>
                      ) : null}
                      <MoreMenu
                        label={t("weekActions", { week: week + 1 })}
                        testId={`programme-week-menu-${week}`}
                        items={[
                          ...(weeks > 1 ? [{ label: t("copyTo"), onSelect: () => actions.copyTo(week) }] : []),
                          ...(actions.canMove ? [{ label: t("reorder"), onSelect: () => actions.move(week) }] : []),
                          ...(actions.canDelete ? [{ label: t("deleteWeek"), onSelect: () => actions.remove(week), tone: "danger" as const }] : []),
                        ]}
                      />
                    </span>
                  </div>
                  {Array.from({ length: DAYS_PER_WEEK }, (_, slot) => {
                    const day = week * DAYS_PER_WEEK + slot;
                    return (
                      <DayCell
                        key={day}
                        ref={(node) => {
                          if (node) cells.current.set(day, node);
                          else cells.current.delete(day);
                        }}
                        day={day}
                        ids={workoutsOn(days, day)}
                        byId={byId}
                        focused={day === current}
                        selected={selected.has(day)}
                        over={over === day}
                        onClick={(shift) => activate(day, shift)}
                        onFocus={() => setCursor(day)}
                        onDragOver={(event) => {
                          if (!event.dataTransfer.types.includes(WOD_MIME)) return;
                          event.preventDefault();
                          event.dataTransfer.dropEffect = "copy";
                          setOver(day);
                        }}
                        onDragLeave={() => setOver((value) => (value === day ? null : value))}
                        onDrop={(event) => dropOn(day, event)}
                      />
                    );
                  })}
                </div>
              );
            })}
          </div>
        </div>

        {selected.size ? (
          <div className="flex flex-wrap items-center gap-2 rounded-2xl px-3 py-2" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }} data-testid="programme-selection">
            <b className="text-sm" style={{ color: "var(--text)" }}>
              {single !== null
                ? t("dayTitle", { week: Math.floor(single / DAYS_PER_WEEK) + 1, day: (single % DAYS_PER_WEEK) + 1 })
                : t("selectedDays", { count: selected.size })}
            </b>
            {single !== null
              ? workoutsOn(days, single).map((id) => (
                  <span key={id} className="flex items-center gap-1 rounded-full py-0.5 pe-1 ps-2.5 text-xs font-semibold" style={{ background: "var(--panel)", color: "var(--text)" }}>
                    {byId.get(id)?.title ?? tp("unknownWod")}
                    <button
                      type="button"
                      onClick={() => onChange({ days: setDay(days, single, workoutsOn(days, single).filter((entry) => entry !== id)) })}
                      aria-label={tp("removeWod", { title: byId.get(id)?.title ?? tp("unknownWod") })}
                      className="grid h-6 w-6 place-items-center rounded-full"
                      style={{ color: "var(--muted)" }}
                    >
                      <span aria-hidden="true">×</span>
                    </button>
                  </span>
                ))
              : null}
            <span className="flex-1" />
            <button
              type="button"
              className="rounded-lg px-2 py-1 text-xs font-semibold"
              style={{ color: "var(--text-soft)" }}
              onClick={() => {
                onChange({ days: restDays(days, [...selected]) });
                say(t("rested", { count: selected.size }));
              }}
            >
              {tp("rest")}
            </button>
            <button type="button" className="rounded-lg px-2 py-1 text-xs font-semibold" style={{ color: "var(--text-soft)" }} onClick={() => setSelection([])}>
              {t("clearSelection")}
            </button>
          </div>
        ) : null}

        <div className="flex flex-wrap gap-2">
          {weeks < MAX_WEEKS ? (
            <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} onClick={() => onChange({ weeks: addWeek(weeks) })} data-testid="programme-add-week">
              {tp("addWeek")}
            </button>
          ) : null}
        </div>

        <p id={hintId} className="flex flex-wrap gap-x-5 gap-y-1 text-xs" style={{ color: "var(--dim)" }}>
          <span>{t("hintDrag")}</span>
          <span>{t.rich("hintCopy", { k: (chunks) => <Kbd>{chunks}</Kbd> })}</span>
          <span>{t.rich("hintShift", { k: (chunks) => <Kbd>{chunks}</Kbd> })}</span>
          <span>{t.rich("hintDel", { k: (chunks) => <Kbd>{chunks}</Kbd> })}</span>
        </p>
        <p id={helpId} className="sr-only">{t("keyboardHelp")}</p>
      </section>
      {actions.dialogs}
    </div>
  );
}

function Kbd({ children }: { children: ReactNode }) {
  return (
    <kbd className="rounded-md px-1.5 py-0.5 font-sans text-[0.7rem] font-semibold" style={{ border: "1px solid var(--border)", background: "var(--panel)", color: "var(--text-soft)" }}>
      {children}
    </kbd>
  );
}

function DayCell({
  ref,
  day,
  ids,
  byId,
  focused,
  selected,
  over,
  onClick,
  onFocus,
  onDragOver,
  onDragLeave,
  onDrop,
}: {
  ref: (node: HTMLDivElement | null) => void;
  day: number;
  ids: string[];
  byId: Map<string, LibraryWod>;
  focused: boolean;
  selected: boolean;
  over: boolean;
  onClick: (shift: boolean) => void;
  onFocus: () => void;
  onDragOver: (event: DragEvent<HTMLDivElement>) => void;
  onDragLeave: () => void;
  onDrop: (event: DragEvent<HTMLDivElement>) => void;
}) {
  const t = useTranslations("Programmes.editor2");
  const tp = useTranslations("Programmes");
  const labels = useWorkoutTypeLabels();
  const titles = ids.map((id) => byId.get(id)?.title ?? tp("unknownWod"));
  const week = Math.floor(day / DAYS_PER_WEEK) + 1;
  const slot = (day % DAYS_PER_WEEK) + 1;
  return (
    <div
      ref={ref}
      role="gridcell"
      tabIndex={focused ? 0 : -1}
      aria-selected={selected}
      aria-label={t("cellLabel", { week, day: slot, content: titles.length ? titles.join(", ") : tp("rest") })}
      aria-keyshortcuts={KEY_SHORTCUTS}
      onClick={(event) => onClick(event.shiftKey)}
      onFocus={onFocus}
      onDragOver={onDragOver}
      onDragLeave={onDragLeave}
      onDrop={onDrop}
      className="flex min-h-16 cursor-pointer flex-col gap-1 overflow-hidden rounded-xl p-1.5 outline-none focus-visible:ring-2"
      style={{
        background: selected ? "color-mix(in srgb, var(--primary) 14%, var(--panel))" : ids.length ? "var(--panel)" : "var(--panel-muted)",
        border: `1px ${over ? "dashed" : "solid"} ${selected || over ? "var(--primary)" : "var(--border)"}`,
        ["--tw-ring-color" as string]: "var(--primary)",
      }}
      data-testid={`programme-cell-${day}`}
    >
      {ids.length === 0 ? (
        <span className="m-auto text-xs" style={{ color: "var(--dim)" }}>{tp("rest")}</span>
      ) : (
        ids.map((id, index) => {
          const wod = byId.get(id);
          return (
            <span key={id} className="flex min-w-0 items-stretch gap-1.5">
              <i aria-hidden="true" className="w-1 shrink-0 rounded-full" style={{ background: wod ? workoutTypeColor(wod.type) : "var(--dim)" }} />
              <span className="min-w-0">
                <span className="block truncate text-xs font-semibold" style={{ color: "var(--text)" }}>{titles[index]}</span>
                {wod && ids.length === 1 ? <span className="block truncate text-[0.7rem]" style={{ color: "var(--muted)" }}>{labels.family(wod.type)}</span> : null}
              </span>
            </span>
          );
        })
      )}
    </div>
  );
}

function Library({ library, loading, armed, onChoose }: { library: LibraryWod[]; loading: boolean; armed: string | null; onChoose: (id: string) => void }) {
  const t = useTranslations("Programmes.editor2");
  const tp = useTranslations("Programmes");
  const labels = useWorkoutTypeLabels();
  const [query, setQuery] = useState("");
  const [family, setFamily] = useState<WorkoutTypeFamily | null>(null);
  const families = libraryFamilies(library);
  const shown = filterLibrary(library, query, family).slice(0, 80);
  return (
    <aside className="flex max-h-[calc(100dvh-12rem)] min-w-0 flex-col gap-2 overflow-hidden rounded-2xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} aria-label={t("library")}>
      <h2 className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("library")}</h2>
      <input
        className={inputClass}
        style={inputStyle}
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder={t("search")}
        aria-label={t("searchLibrary")}
        data-testid="programme-library-search"
      />
      {families.length > 1 ? (
        <div className="flex flex-wrap gap-1" role="group" aria-label={t("familyFilter")}>
          {[null, ...families].map((value) => {
            const on = family === value;
            return (
              <button
                key={value ?? "all"}
                type="button"
                aria-pressed={on}
                onClick={() => setFamily(value)}
                className="rounded-full px-2.5 py-1 text-xs font-semibold"
                style={{
                  background: on ? "var(--spark)" : "var(--panel-muted)",
                  color: on ? "var(--spark-contrast)" : "var(--text-soft)",
                }}
              >
                {value ? labels.family(value) : t("allFamilies")}
              </button>
            );
          })}
        </div>
      ) : null}
      <ul className="-mx-1 flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto px-1">
        {loading ? <li className="text-sm" style={{ color: "var(--dim)" }}>{tp("loading")}</li> : null}
        {!loading && shown.length === 0 ? (
          <li className="text-sm" style={{ color: "var(--dim)" }}>{library.length ? tp("noWods") : t("libraryEmpty")}</li>
        ) : null}
        {shown.map((wod) => (
          <li key={wod.id}>
            <button
              type="button"
              draggable
              onDragStart={(event) => {
                event.dataTransfer.setData(WOD_MIME, wod.id);
                event.dataTransfer.setData("text/plain", wod.id);
                event.dataTransfer.effectAllowed = "copy";
              }}
              onClick={() => onChoose(wod.id)}
              aria-pressed={armed === wod.id}
              className="flex min-h-11 w-full cursor-grab items-center rounded-xl px-2 py-1 text-start"
              style={{
                border: `1px solid ${armed === wod.id ? "var(--primary)" : "var(--border)"}`,
                background: armed === wod.id ? "color-mix(in srgb, var(--primary) 12%, var(--panel))" : "transparent",
              }}
              data-testid={`programme-library-${wod.id}`}
            >
              <WodLine wod={wod} fallbackTitle={tp("unknownWod")} />
            </button>
          </li>
        ))}
      </ul>
    </aside>
  );
}
