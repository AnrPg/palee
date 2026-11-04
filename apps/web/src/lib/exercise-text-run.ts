import { fold, fuzzy } from "@/lib/structured-plan/fuzzy";

/**
 * ADR-461: the words just typed before the caret in a free text (a note),
 * the candidates for an exercise name. A run stops at a line break, a
 * punctuation mark or a word that starts with a digit ("5x5 back sq" →
 * "back sq", while "T2B" stays one word); it holds at most
 * three words and needs three letters or digits. `null` while the caret is inside a
 * word (more letters follow) or nothing fits.
 */
export type TextRun = { from: number; to: number; words: { text: string; at: number }[]; query: string };

const STOP = /[\n\r,;.:!?()[\]{}"«»@+*/=#%]/u;
const LETTER = /[\p{L}&]/u;
const MAX_WORDS = 3;

export function textRunAt(text: string, caret: number): TextRun | null {
  if (caret < 0 || caret > text.length) return null;
  if (caret < text.length && LETTER.test(text[caret] ?? "")) return null;
  let start = caret;
  while (start > 0 && !STOP.test(text[start - 1]!)) start -= 1;
  const segment = text.slice(start, caret);
  const words: { text: string; at: number }[] = [];
  for (const match of segment.matchAll(/[^\s]+/gu)) words.push({ text: match[0], at: start + (match.index ?? 0) });
  let lastNumber = -1;
  words.forEach((w, i) => {
    if (/^\d/.test(w.text)) lastNumber = i;
  });
  const last = words.slice(lastNumber + 1).slice(-MAX_WORDS);
  if (last.length === 0) return null;
  // The caret must end the last word (no trailing space: the person moved on).
  const tail = last[last.length - 1]!;
  if (tail.at + tail.text.length !== caret) return null;
  if (!last.some((w) => LETTER.test(w.text))) return null;
  // The server is asked with the last two words, the usual length of a name.
  const queryWords = last.slice(-2);
  const query = queryWords.map((w) => w.text).join(" ");
  if (fold(query).replace(/[^\p{L}\p{N}&]/gu, "").length < 3) return null;
  return { from: last[0]!.at, to: caret, words: last, query };
}

/**
 * Where a picked name replaces the run: the longest trailing words of the
 * run that the name matches (so "did back sq" replaces only "back sq"), or
 * `null` when no suffix matches. `exact` when that suffix already is the name.
 */
export function replacementFor(run: TextRun, name: string): { from: number; exact: boolean } | null {
  for (let n = run.words.length; n >= 1; n -= 1) {
    const words = run.words.slice(-n);
    const typed = words.map((w) => w.text).join(" ");
    if (fuzzy(typed, name)) return { from: words[0]!.at, exact: fold(typed) === fold(name) };
  }
  return null;
}
