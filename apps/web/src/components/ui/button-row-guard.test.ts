import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import { describe, expect, it } from "vitest";

/**
 * Button row guard (ANR 2026-11-07): on a narrow phone the «Άκυρο / Άρση
 * ακολούθησης» pair ran off the screen. Every flex row that holds two or more
 * buttons with a written label must be able to wrap (`flex-wrap`, or
 * `buttonRow` / `itemRow` / `itemRowActions` from `ui/rows`) or stack
 * (`flex-col`, `grid`). Rows of icon-only buttons (prev/next arrows, steppers)
 * are fine: their width is fixed and small.
 *
 * The check reads the JSX source line by line: an element that opens with a
 * `className` holding `flex` and is followed by its direct children at one
 * deeper indent. Formatting is Prettier's, so the indent is reliable.
 */

const root = join(__dirname, "..", "..");

const WRAPS = /\b(flex-wrap|flex-col|grid|buttonRow|itemRow|itemRowActions)\b/;
const OPENS = /^(\s*)<(div|footer|span|section|nav|p|li|header|form)\b[^>]*className=\{?[`"]?([^`"}]*)/;
const BUTTON = /^<(button|Link|[A-Z]\w*Button|[A-Z]\w*Action)\b/;
// What a reader sees written on a button: a translation, a label prop, children or literal text.
const WRITTEN = /\{\s*(?:[\w.]+\s*\?\s*)?(?:t\w*|i18n|label\w*)\(|\{\s*(?:label|children)\s*\}|(?<!=)>\s*[\p{L}][^<{]*</u;
const ATTRIBUTES = /\b(aria-label|title|alt|placeholder)=\{[^}]*\}|\b(aria-label|title|alt|placeholder)="[^"]*"/g;

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return files(path);
    return name.endsWith(".tsx") && !name.includes(".test.") ? [path] : [];
  });
}

/** Rows that hold two or more written buttons and can neither wrap nor stack. */
function rowsThatCannotWrap(source: string): number[] {
  const lines = source.split("\n");
  const found: number[] = [];
  lines.forEach((line, index) => {
    const open = OPENS.exec(line);
    if (!open || line.trimEnd().endsWith("/>")) return;
    const classes = open[3].split(/\s+/);
    if (!classes.includes("flex") && !classes.includes("inline-flex")) return;
    if (WRAPS.test(line)) return;
    const indent = open[1].length;
    const children: string[][] = [];
    let childIndent: number | null = null;
    for (let at = index + 1; at < lines.length; at += 1) {
      const next = lines[at];
      if (next.trim() === "") continue;
      const depth = next.length - next.trimStart().length;
      if (depth <= indent) break;
      childIndent ??= depth;
      // Prettier puts a multi-line tag's closing `>` at the tag's own indent: it continues that child.
      if (depth === childIndent && /^(<[A-Za-z]|\{)/.test(next.trim())) children.push([next.trim()]);
      else children.at(-1)?.push(next.trim());
    }
    const written = children.filter(([head, ...body]) => BUTTON.test(head) && WRITTEN.test([head, ...body].join(" ").replace(ATTRIBUTES, "")));
    if (written.length >= 2) found.push(index + 1);
  });
  return found;
}

describe("button row guard", () => {
  it("spots a row of written buttons that cannot wrap, and leaves wrapping or icon rows alone", () => {
    const row = (classes: string, a: string, b: string) =>
      `  <div className="${classes}">\n    <button type="button">\n      ${a}\n    </button>\n    <button type="button">\n      ${b}\n    </button>\n  </div>`;
    expect(rowsThatCannotWrap(row("flex gap-2", '{t("keep")}', '{t("unfollow")}'))).toEqual([1]);
    expect(rowsThatCannotWrap(row("flex gap-2", "Άκυρο", "Διαγραφή"))).toEqual([1]);
    expect(rowsThatCannotWrap(row("flex flex-wrap gap-2", '{t("keep")}', '{t("unfollow")}'))).toEqual([]);
    expect(rowsThatCannotWrap(row("flex flex-col gap-2", '{t("keep")}', '{t("unfollow")}'))).toEqual([]);
    expect(rowsThatCannotWrap(row("flex gap-1", '<Icon name="left" />', '<Icon name="right" />'))).toEqual([]);
    expect(rowsThatCannotWrap('  <div className={buttonRow}>\n    <button>{t("a")}</button>\n    <button>{t("b")}</button>\n  </div>')).toEqual([]);
  });

  it("finds no button row in the app that would run off a narrow phone", () => {
    const offenders = files(join(root, "app"))
      .concat(files(join(root, "components")))
      .flatMap((path) => rowsThatCannotWrap(readFileSync(path, "utf8")).map((line) => `${relative(root, path)}:${line}`));
    expect(offenders).toEqual([]);
  });
});
