"use client";

import { useCallback, useId, useMemo, useState, type KeyboardEvent, type RefObject, type TextareaHTMLAttributes } from "react";
import { useTranslations } from "next-intl";

import type { ExerciseSuggestionGroup } from "@/api/exercise-suggestions";
import { HighlightedName } from "@/components/exercises/ExerciseNameInput";
import { rankExerciseSuggestions, useExerciseSuggestions } from "@/hooks/useExerciseSuggestions";
import { replacementFor, textRunAt } from "@/lib/exercise-text-run";
import { fuzzy } from "@/lib/structured-plan/fuzzy";
import { caretCoordinates } from "@/lib/textarea-caret";

const MAX_ITEMS = 6;

type Item = { name: string; from: number; marks: [number, number][]; source: string };

/**
 * ADR-461: inline exercise suggestions in a free text (a note). While the
 * words just typed before the caret fuzzy-match exercise names (the
 * person's own, their box's, Palee's), a small list opens at the caret;
 * ↑/↓ move, Enter or Tab replace those words with the name, Esc closes it
 * until the words change. With no list open, every key types as usual.
 */
export function useExerciseTextSuggestions(
  textareaRef: RefObject<HTMLTextAreaElement | null>,
  value: string,
  onValueChange: (text: string) => void,
  options: { organizationId?: string | null; enabled?: boolean } = {},
) {
  const t = useTranslations("ExerciseNameInput");
  const listId = useId();
  const [caret, setCaret] = useState<number | null>(null);
  const [active, setActive] = useState(0);
  const [dismissed, setDismissed] = useState<string | null>(null);
  // Where the list opens: measured at the start of the run when the caret moves (an event, never during render).
  const [position, setPosition] = useState<{ top: number; left: number } | null>(null);
  const run = useMemo(() => (caret === null ? null : textRunAt(value, caret)), [value, caret]);
  const runKey = run ? `${run.from}:${value.slice(run.from, run.to)}` : null;
  const enabled = (options.enabled ?? true) && Boolean(run) && runKey !== dismissed;
  const { groups } = useExerciseSuggestions(run?.query ?? "", { organizationId: options.organizationId, enabled, limit: 4 });

  const items = useMemo(() => (run && enabled ? itemsFor(run, groups, value) : []), [run, enabled, groups, value]);
  const open = items.length > 0;
  const activeIndex = Math.min(active, Math.max(items.length - 1, 0));

  const syncCaret = useCallback(() => {
    const el = textareaRef.current;
    if (!el) return;
    const at = el.selectionStart === el.selectionEnd ? el.selectionStart : null;
    setCaret(at);
    setActive(0);
    const current = at === null ? null : textRunAt(el.value, at);
    if (!current) return setPosition(null);
    const coords = caretCoordinates(el, current.from);
    setPosition({
      top: el.offsetTop + coords.top + coords.height + 4,
      left: Math.max(0, Math.min(el.offsetLeft + coords.left, el.offsetLeft + el.clientWidth - 220)),
    });
  }, [textareaRef]);

  const accept = useCallback(
    (item: Item) => {
      if (!run) return;
      const next = value.slice(0, item.from) + item.name + value.slice(run.to);
      const position = item.from + item.name.length;
      onValueChange(next);
      setCaret(position);
      setDismissed(`${item.from}:${item.name}`);
      window.requestAnimationFrame(() => textareaRef.current?.setSelectionRange(position, position));
    },
    [run, value, onValueChange, textareaRef],
  );

  const onKeyDown = useCallback(
    (event: KeyboardEvent<HTMLTextAreaElement>) => {
      if (!open || event.altKey || event.ctrlKey || event.metaKey) return;
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        const step = event.key === "ArrowDown" ? 1 : -1;
        setActive((current) => (Math.min(current, items.length - 1) + step + items.length) % items.length);
      } else if ((event.key === "Enter" || event.key === "Tab") && !event.shiftKey) {
        event.preventDefault();
        accept(items[activeIndex]!);
      } else if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        setDismissed(runKey);
      }
    },
    [open, items, activeIndex, accept, runKey],
  );

  const textareaProps: Pick<
    TextareaHTMLAttributes<HTMLTextAreaElement>,
    "onKeyDown" | "onSelect" | "onInput" | "onBlur" | "aria-autocomplete" | "aria-controls" | "aria-expanded" | "aria-activedescendant"
  > = {
    onKeyDown,
    onSelect: syncCaret,
    onInput: syncCaret,
    onBlur: () => setCaret(null),
    "aria-autocomplete": "list",
    "aria-controls": open ? listId : undefined,
    "aria-expanded": open,
    "aria-activedescendant": open ? `${listId}-${activeIndex}` : undefined,
  };

  const menu =
    open && position ? (
      <div
        id={listId}
        role="listbox"
        aria-label={t("listLabel")}
        data-testid="exercise-text-suggestions"
        className="absolute z-(--z-popover) min-w-[220px] max-w-[320px] rounded-2xl py-1 shadow-lg"
        style={{ top: position.top, left: position.left, background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        {items.map((item, index) => (
          <div
            key={`${item.source}-${item.name}`}
            id={`${listId}-${index}`}
            role="option"
            aria-selected={index === activeIndex}
            onMouseDown={(event) => {
              event.preventDefault();
              accept(item);
            }}
            onMouseEnter={() => setActive(index)}
            className="flex cursor-pointer items-baseline justify-between gap-3 px-3 py-1.5 text-sm"
            style={{
              background: index === activeIndex ? "color-mix(in srgb, var(--primary) 14%, transparent)" : "transparent",
              color: "var(--text)",
            }}
          >
            <span className="font-semibold">
              <HighlightedName text={item.name} marks={item.marks} />
            </span>
            <span className="text-xs" style={{ color: "var(--muted)" }}>
              {t(`group.${item.source}`)}
            </span>
          </div>
        ))}
        <div className="px-3 pb-1 pt-1 text-[11px]" style={{ color: "var(--muted)" }}>
          {t("textHint")}
        </div>
      </div>
    ) : null;

  return { textareaProps, menu, open };
}

/** The names to offer for the run (none once the words already are a name), deduplicated. */
function itemsFor(run: NonNullable<ReturnType<typeof textRunAt>>, groups: ExerciseSuggestionGroup[], value: string): Item[] {
  const out: Item[] = [];
  const seen = new Set<string>();
  for (const item of rankExerciseSuggestions(run.query, groups)) {
    const at = replacementFor(run, item.name);
    if (!at) continue;
    if (at.exact) return [];
    const key = item.name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ name: item.name, from: at.from, marks: fuzzy(value.slice(at.from, run.to), item.name)?.marks ?? [], source: item.source });
    if (out.length >= MAX_ITEMS) break;
  }
  return out;
}
