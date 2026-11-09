"use client";

import type { Editor } from "@tiptap/react";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useId, useLayoutEffect, useMemo, useRef, useState, type MutableRefObject } from "react";
import { createPortal } from "react-dom";

import type { ExerciseSuggestionGroup } from "@/api/exercise-suggestions";
import { HighlightedName } from "@/components/exercises/ExerciseNameInput";
import { rankExerciseSuggestions, useExerciseSuggestions } from "@/hooks/useExerciseSuggestions";
import { replacementFor, textRunAt, type TextRun } from "@/lib/exercise-text-run";
import { fold, fuzzy } from "@/lib/structured-plan/fuzzy";

import { EXERCISE_LINK, exerciseGhostKey, type ExerciseGhost } from "./exercise-link";

const MAX_ITEMS = 6;
/** ADR-570: Palee's names first (they feed the muscles), then the box's, then mine. */
const SOURCE_ORDER: ExerciseSuggestionGroup["source"][] = ["palee", "box", "mine"];

export type EditorSuggestion = {
  name: string;
  /** Character offset in the text block where the name replaces the typed words. */
  from: number;
  marks: [number, number][];
  source: ExerciseSuggestionGroup["source"];
  /** The catalog exercise the name links to, if any. */
  ref: string | null;
};

type Caret = { blockStart: number; pos: number; run: TextRun; text: string };

/**
 * ADR-570: exercise suggestions at the caret of the free-text editor, as in
 * a code editor. While the words just typed fuzzy-match exercise names, a
 * list opens under them with the selected name's rest shown grey after the
 * caret. Tab puts the selected name in; ↑/↓ choose, and only after them
 * Enter puts it in (otherwise Enter starts a new line); Esc hides the list
 * until it changes; a tap picks a name. Typing on simply ignores it. A name
 * from the catalog links its words to the exercise (`exerciseLink`).
 */
export function useEditorExerciseSuggestions(
  editor: Editor | null,
  handlerRef: MutableRefObject<((event: KeyboardEvent) => boolean) | null>,
) {
  const t = useTranslations("ExerciseNameInput");
  const listId = useId();
  const [caret, setCaret] = useState<Caret | null>(null);
  // The highlighted name of one list; a new list starts at its first name, not yet chosen with the arrows.
  const [choice, setChoice] = useState({ signature: "", index: 0, navigated: false });
  const [dismissed, setDismissed] = useState<string | null>(null);
  const [position, setPosition] = useState<{ signature: string; top: number; left: number } | null>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!editor) return;
    const sync = () => setCaret(editor.isFocused ? caretOf(editor) : null);
    const blur = () => setCaret(null);
    editor.on("selectionUpdate", sync);
    editor.on("update", sync);
    editor.on("focus", sync);
    editor.on("blur", blur);
    return () => {
      editor.off("selectionUpdate", sync);
      editor.off("update", sync);
      editor.off("focus", sync);
      editor.off("blur", blur);
    };
  }, [editor]);

  const { groups } = useExerciseSuggestions(caret?.run.query ?? "", { enabled: Boolean(caret), limit: 4 });
  const items = useMemo(() => (caret ? suggestionsFor(caret.run, caret.text, groups) : []), [caret, groups]);
  const signature = items.map((item) => `${item.from}:${item.name}`).join("|");
  const open = items.length > 0 && signature !== dismissed;
  const sameList = choice.signature === signature;
  const activeIndex = sameList ? Math.min(choice.index, Math.max(items.length - 1, 0)) : 0;
  const navigated = sameList && choice.navigated;
  const selected = open ? items[activeIndex] ?? null : null;
  const setActive = (index: number, byArrows = false) =>
    setChoice({ signature, index, navigated: byArrows || navigated });

  const accept = useCallback(
    (item: EditorSuggestion) => {
      if (!editor || !caret) return;
      const from = caret.blockStart + item.from;
      const to = caret.pos;
      const type = editor.schema.marks[EXERCISE_LINK];
      editor
        .chain()
        .focus()
        .command(({ tr }) => {
          tr.insertText(item.name, from, to);
          const end = from + item.name.length;
          if (type) {
            tr.removeMark(from, end, type);
            if (item.ref) tr.addMark(from, end, type.create({ ref: item.ref, checked: null }));
          }
          return true;
        })
        .run();
      setDismissed(signature);
    },
    [editor, caret, signature],
  );

  const handleKey = (event: KeyboardEvent) => {
    if (!open || !selected || event.altKey || event.ctrlKey || event.metaKey) return false;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      const step = event.key === "ArrowDown" ? 1 : -1;
      setActive((activeIndex + step + items.length) % items.length, true);
      return true;
    }
    if (event.key === "Tab" && !event.shiftKey) {
      accept(selected);
      return true;
    }
    if (event.key === "Enter" && !event.shiftKey && navigated) {
      accept(selected);
      return true;
    }
    if (event.key === "Escape") {
      setDismissed(signature);
      return true;
    }
    return false;
  };
  // The editor asks the newest handler (it lives outside React).
  useLayoutEffect(() => {
    handlerRef.current = handleKey;
  });

  // The grey rest of the selected name, when it continues what was typed.
  const ghostText = selected && caret ? ghostFor(caret.text.slice(selected.from, caret.run.to), selected.name) : null;
  const ghostPos = caret?.pos ?? null;
  useEffect(() => {
    if (!editor || editor.isDestroyed) return;
    const current = exerciseGhostKey.getState(editor.state);
    const next: ExerciseGhost | null = ghostText && ghostPos !== null ? { pos: ghostPos, text: ghostText } : null;
    if (current?.pos === next?.pos && current?.text === next?.text) return;
    editor.view.dispatch(editor.state.tr.setMeta(exerciseGhostKey, next).setMeta("addToHistory", false));
  }, [editor, ghostText, ghostPos]);

  useLayoutEffect(() => {
    if (!editor || !open || !caret) return;
    const place = () => {
      if (editor.isDestroyed) return;
      const start = editor.view.coordsAtPos(Math.min(caret.blockStart + caret.run.from, editor.state.doc.content.size));
      const width = menuRef.current?.getBoundingClientRect().width ?? 260;
      const height = menuRef.current?.getBoundingClientRect().height ?? 0;
      const below = start.bottom + 4;
      const top = below + height > window.innerHeight - 8 && start.top - 4 - height > 8 ? start.top - 4 - height : below;
      setPosition({ signature, top, left: Math.max(8, Math.min(start.left, window.innerWidth - width - 8)) });
    };
    place();
    window.addEventListener("resize", place);
    window.addEventListener("scroll", place, true);
    return () => {
      window.removeEventListener("resize", place);
      window.removeEventListener("scroll", place, true);
    };
  }, [editor, open, caret, signature]);

  // A position measured for an earlier list is not shown for this one.
  const shown = position && position.signature === signature ? position : null;
  const menu =
    open && typeof document !== "undefined"
      ? createPortal(
          <div
            ref={menuRef}
            id={listId}
            role="listbox"
            aria-label={t("listLabel")}
            data-testid="editor-exercise-suggestions"
            className="fixed min-w-[220px] max-w-[min(340px,calc(100vw-1rem))] rounded-2xl py-1 shadow-lg"
            style={{
              zIndex: "var(--z-popover)",
              top: shown?.top ?? -9999,
              left: shown?.left ?? -9999,
              visibility: shown ? "visible" : "hidden",
              background: "var(--panel)",
              border: "1px solid var(--border)",
            }}
          >
            {items.map((item, index) => (
              <div
                key={`${item.source}-${item.name}`}
                id={`${listId}-${index}`}
                role="option"
                aria-selected={index === activeIndex}
                // Keeps the caret in the text; the click (a tap too) picks.
                onMouseDown={(event) => event.preventDefault()}
                onClick={() => accept(item)}
                onMouseEnter={() => setActive(index)}
                className="flex min-h-9 cursor-pointer items-center justify-between gap-3 px-3 py-1.5 text-sm"
                style={{
                  background: index === activeIndex ? "color-mix(in srgb, var(--primary) 14%, transparent)" : "transparent",
                  color: "var(--text)",
                }}
              >
                <span className="font-semibold">
                  <HighlightedName text={item.name} marks={item.marks} />
                </span>
                <span className="shrink-0 text-xs" style={{ color: "var(--muted)" }}>
                  {t(`group.${item.source}`)}
                </span>
              </div>
            ))}
            <div className="px-3 pb-1 pt-1 text-[11px]" style={{ color: "var(--muted)" }}>
              {t("editorHint")}
            </div>
          </div>,
          document.body,
        )
      : null;

  return { menu, open };
}

/** The words before the caret in its text block, as a run to suggest for (or null). */
export function caretOf(editor: Editor): Caret | null {
  const { selection } = editor.state;
  if (!selection.empty) return null;
  const $pos = selection.$from;
  const block = $pos.parent;
  if (!block.isTextblock || block.type.spec.code) return null;
  // Text and hard breaks take one position per character, so offsets are positions.
  const text = block.textBetween(0, block.content.size, undefined, "\n");
  if (text.length !== block.content.size) return null;
  const run = textRunAt(text, $pos.parentOffset);
  return run ? { blockStart: $pos.start(), pos: selection.from, run, text } : null;
}

/** The names to offer for a run, Palee's first; none once the words already are a name. */
export function suggestionsFor(run: TextRun, text: string, groups: ExerciseSuggestionGroup[]): EditorSuggestion[] {
  const ordered = SOURCE_ORDER.flatMap((source) => groups.filter((group) => group.source === source));
  const out: EditorSuggestion[] = [];
  const seen = new Set<string>();
  for (const item of rankExerciseSuggestions(run.query, ordered)) {
    const at = replacementFor(run, item.name);
    if (!at) continue;
    if (at.exact) return [];
    const key = fold(item.name);
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({
      name: item.name,
      from: at.from,
      marks: fuzzy(text.slice(at.from, run.to), item.name)?.marks ?? [],
      source: item.source,
      ref: item.catalog_slug ?? null,
    });
    if (out.length >= MAX_ITEMS) break;
  }
  return out;
}

/** What the grey completion shows: the rest of `name` when `typed` starts it, else nothing. */
export function ghostFor(typed: string, name: string): string | null {
  if (!typed || name.length <= typed.length) return null;
  return fold(name.slice(0, typed.length)) === fold(typed) ? name.slice(typed.length) : null;
}
