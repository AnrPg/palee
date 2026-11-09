import { Extension, Mark, mergeAttributes } from "@tiptap/core";
import type { Node as PmNode } from "@tiptap/pm/model";
import { Plugin, PluginKey, type EditorState, type Transaction } from "@tiptap/pm/state";
import { Decoration, DecorationSet } from "@tiptap/pm/view";

/**
 * ADR-570: the words of a free-text workout tied to a catalog exercise.
 *
 * `ref` is the exercise (picked from the suggestions or confirmed before
 * publishing); `ref: null` is a match the coach answered «Όχι» (the words
 * stay plain text, shown orange-red, and are not asked about again);
 * `checked` holds the words a coach confirmed for a link whose text no
 * longer names its exercise, so the server asks only once. The server reads
 * the same mark from `free_text_document` (Palee.Workouts.Domain.FreeTextDocument).
 *
 * The link survives edits of its words: letters typed right against it join
 * it (`ExerciseLinkGlue`), so it goes away only when all its words do.
 */
export const EXERCISE_LINK = "exerciseLink";

export const ExerciseLink = Mark.create({
  name: EXERCISE_LINK,
  inclusive: false,
  // Links never nest or overlap.
  excludes: EXERCISE_LINK,

  addAttributes() {
    return {
      ref: {
        default: null,
        parseHTML: (element) => element.getAttribute("data-exercise-ref") || null,
        renderHTML: (attributes) => (attributes.ref ? { "data-exercise-ref": attributes.ref } : {}),
      },
      checked: {
        default: null,
        parseHTML: (element) => element.getAttribute("data-exercise-checked") || null,
        renderHTML: (attributes) => (attributes.checked ? { "data-exercise-checked": attributes.checked } : {}),
      },
    };
  },

  parseHTML() {
    return [{ tag: "span[data-exercise-link]" }];
  },

  renderHTML({ HTMLAttributes, mark }) {
    const rejected = !mark.attrs.ref;
    return [
      "span",
      mergeAttributes(HTMLAttributes, {
        "data-exercise-link": "",
        class: rejected ? "exercise-link exercise-link-rejected" : "exercise-link",
      }),
      0,
    ];
  },

  addProseMirrorPlugins() {
    return [exerciseLinkGlue()];
  },
});

const WORD_CHAR = /[\p{L}\p{N}'’-]/u;

/** Letters typed right before or after a link (no space between) become part of it. */
function exerciseLinkGlue() {
  return new Plugin({
    key: new PluginKey("exerciseLinkGlue"),
    appendTransaction(transactions, _old, state) {
      if (!transactions.some((tr) => tr.docChanged)) return null;
      const ranges = changedRanges(transactions, state);
      if (ranges.length === 0) return null;
      let tr: Transaction | null = null;
      const seen = new Set<number>();
      for (const { from, to } of ranges) {
        state.doc.nodesBetween(from, to, (node, pos) => {
          if (!node.isTextblock) return true;
          if (seen.has(pos)) return false;
          seen.add(pos);
          for (const grow of growths(node, pos + 1, state)) {
            tr ??= state.tr;
            tr.addMark(grow.from, grow.to, grow.mark);
          }
          return false;
        });
      }
      return tr ? (tr as Transaction).setMeta("addToHistory", false) : null;
    },
  });
}

function changedRanges(transactions: readonly Transaction[], state: EditorState) {
  const out: { from: number; to: number }[] = [];
  transactions.forEach((tr, index) => {
    tr.mapping.maps.forEach((map, mapIndex) => {
      map.forEach((_oldStart, _oldEnd, newStart, newEnd) => {
        // Into the final document: through the rest of this transaction and the later ones.
        let from = newStart;
        let to = newEnd;
        const rest = tr.mapping.slice(mapIndex + 1);
        from = rest.map(from, -1);
        to = rest.map(to, 1);
        for (const later of transactions.slice(index + 1)) {
          from = later.mapping.map(from, -1);
          to = later.mapping.map(to, 1);
        }
        const size = state.doc.content.size;
        out.push({ from: Math.max(0, Math.min(from, size)), to: Math.max(0, Math.min(to, size)) });
      });
    });
  });
  return out;
}

/** The unlinked word characters touching each link of a text block, to add to it. */
function growths(block: PmNode, start: number, state: EditorState) {
  const type = state.schema.marks[EXERCISE_LINK];
  if (!type) return [];
  // One entry per position of the block: its character (or null) and its link.
  const chars: { char: string | null; link: ReturnType<typeof type.isInSet> | undefined }[] = [];
  block.forEach((child) => {
    if (child.isText && child.text) {
      const link = type.isInSet(child.marks);
      for (const char of child.text) {
        chars.push({ char, link });
        // A character outside the BMP takes two positions.
        if (char.length > 1) chars.push({ char: null, link });
      }
    } else {
      for (let i = 0; i < child.nodeSize; i += 1) chars.push({ char: null, link: undefined });
    }
  });
  const out: { from: number; to: number; mark: NonNullable<ReturnType<typeof type.isInSet>> }[] = [];
  for (let i = 0; i < chars.length; i += 1) {
    const link = chars[i]!.link;
    if (!link || chars[i - 1]?.link === link) continue;
    let end = i;
    while (end + 1 < chars.length && chars[end + 1]!.link === link) end += 1;
    let left = i;
    while (left > 0 && !chars[left - 1]!.link && WORD_CHAR.test(chars[left - 1]!.char ?? "")) left -= 1;
    let right = end;
    while (right + 1 < chars.length && !chars[right + 1]!.link && WORD_CHAR.test(chars[right + 1]!.char ?? "")) right += 1;
    if (left < i) out.push({ from: start + left, to: start + i, mark: link });
    if (right > end) out.push({ from: start + end + 1, to: start + right + 1, mark: link });
    i = end;
  }
  return out;
}

/** The rest of the selected suggestion, shown grey after the caret. */
export const exerciseGhostKey = new PluginKey<ExerciseGhost | null>("exerciseGhost");
export type ExerciseGhost = { pos: number; text: string };

/**
 * The editor side of the inline suggestions: the grey completion after the
 * caret and the keys the open list takes (`handler`, set by the React hook,
 * returns true for a key it used).
 */
export const ExerciseSuggestKeys = Extension.create<{ handler: { current: ((event: KeyboardEvent) => boolean) | null } }>({
  name: "exerciseSuggestKeys",
  // Before the Enter/Tab keymaps of the other extensions.
  priority: 1000,

  addOptions() {
    return { handler: { current: null } };
  },

  addProseMirrorPlugins() {
    const handler = this.options.handler;
    return [
      new Plugin<ExerciseGhost | null>({
        key: exerciseGhostKey,
        state: {
          init: () => null,
          apply(tr, value) {
            const meta = tr.getMeta(exerciseGhostKey) as ExerciseGhost | null | undefined;
            if (meta !== undefined) return meta;
            // Any typing or moving clears it until the list says what to show.
            return tr.docChanged || tr.selectionSet ? null : value;
          },
        },
        props: {
          handleKeyDown: (_view, event) => handler.current?.(event) ?? false,
          decorations(state) {
            const ghost = exerciseGhostKey.getState(state);
            if (!ghost || ghost.pos > state.doc.content.size) return null;
            return DecorationSet.create(state.doc, [
              Decoration.widget(
                ghost.pos,
                () => {
                  const span = document.createElement("span");
                  span.className = "exercise-ghost";
                  span.setAttribute("aria-hidden", "true");
                  span.setAttribute("data-testid", "exercise-ghost");
                  span.textContent = ghost.text;
                  return span;
                },
                { side: 1, key: `ghost-${ghost.text}` },
              ),
            ]);
          },
        },
      }),
    ];
  },
});

/** The text blocks the server counts as lines (Palee.Workouts.Domain.FreeTextDocument), in order. */
const LINE_BLOCKS = new Set(["paragraph", "heading", "codeBlock"]);

export type LinkSpan = { line: number; from: number; to: number; typed: string; ref: string | null; checked: string | null };

/**
 * Puts the coach's answers into the document as links, in one undoable
 * step. A span is found by its line and character offsets; if the words
 * moved since the check, the first place in that line holding them.
 * Returns how many spans were linked.
 */
export function applyExerciseLinks(state: EditorState, spans: LinkSpan[]): { tr: Transaction; applied: number } {
  const tr = state.tr;
  const type = state.schema.marks[EXERCISE_LINK];
  if (!type || spans.length === 0) return { tr, applied: 0 };
  const lines: { start: number; text: string }[] = [];
  state.doc.descendants((node, pos) => {
    if (!node.isTextblock) return true;
    if (LINE_BLOCKS.has(node.type.name)) lines.push({ start: pos + 1, text: node.textBetween(0, node.content.size, undefined, "\n") });
    return false;
  });
  let applied = 0;
  for (const span of spans) {
    const line = lines[span.line];
    if (!line || line.text.length === 0) continue;
    const at = line.text.slice(span.from, span.to) === span.typed ? span.from : line.text.indexOf(span.typed);
    if (at < 0) continue;
    tr.addMark(line.start + at, line.start + at + span.typed.length, type.create({ ref: span.ref, checked: span.checked }));
    applied += 1;
  }
  return { tr, applied };
}
