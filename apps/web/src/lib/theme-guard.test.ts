import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import { beforeAll, describe, expect, it } from "vitest";

import { APP_THEMES, cssVariablesForTheme } from "./theme";

/**
 * Every colour comes from the theme (src/lib/theme.ts → CSS variables).
 * This guard fails on any colour literal anywhere else in the web sources,
 * so no picker, scrollbar or badge drifts off-theme (docs/brand/THEME.md).
 * A box's website has its own palettes (ADR-530): they come from
 * box-site/templates/palettes.ts as `--s-*` variables, the only other source.
 *
 * Both checks scan the whole source tree, so their cost grows with the code.
 * The tree is read once for both, each file is scanned as one string (line
 * numbers are worked out only for a hit), and the scan has its own timeout,
 * well above what a slow, fully loaded CI runner needs.
 */

const TREE_SCAN_TIMEOUT_MS = 60_000;

const SOURCE_ROOT = join(__dirname, "..");
const THEME_SOURCES = new Set(["lib/theme.ts", "components/box-site/templates/palettes.ts"]);
const SKIPPED_DIRECTORIES = new Set(["api/generated"]);
const CHECKED_EXTENSIONS = [".ts", ".tsx", ".css"];

const NAMED_COLOURS =
  "white|black|red|green|blue|yellow|orange|purple|pink|gray|grey|silver|maroon|navy|teal|olive|lime|aqua|fuchsia|gold|crimson";
const TAILWIND_PALETTE =
  "white|black|slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose";

const RULES: { name: string; pattern: RegExp }[] = [
  { name: "hex colour", pattern: /(?<![\w&])#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})(?![\w-])/g },
  // A template value (`hsl(${hue} …)`) is a literal colour too, just computed.
  { name: "rgb/hsl colour", pattern: /\b(?:rgba?|hsla?|hwb|lab|lch|oklch|oklab)\(\s*(?:[\d.]|\$\{)/g },
  { name: "RGB channels", pattern: /\bset(?:Text|Fill|Draw)Color\(\s*\d|\bcolor:\s*\[\s*\d{1,3},/g },
  // Whitespace without newlines: a colour word must sit on one line, as before files were scanned whole.
  { name: "named colour", pattern: new RegExp(`(?:["'\`:][^\\S\\n]*|[^\\S\\n])(?:${NAMED_COLOURS})(?=["'\`;,)]|[^\\S\\n])`, "g") },
  {
    name: "Tailwind palette class",
    pattern: new RegExp(
      `\\b(?:bg|text|border|from|to|via|ring|fill|stroke|shadow|outline|decoration|divide|caret|accent|placeholder)-(?:${TAILWIND_PALETTE})(?:-\\d{2,3})?(?:\\/\\d+)?\\b`,
      "g",
    ),
  },
];

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    const relativePath = relative(SOURCE_ROOT, path);
    if (statSync(path).isDirectory()) return SKIPPED_DIRECTORIES.has(relativePath) ? [] : sourceFiles(path);
    if (!CHECKED_EXTENSIONS.some((extension) => entry.endsWith(extension))) return [];
    if (entry.includes(".test.") || THEME_SOURCES.has(relativePath)) return [];
    return [path];
  });
}

// Comments may name colours ("the green flash"); only code counts.
function withoutComments(source: string) {
  return source.replace(/\/\*[\s\S]*?\*\//g, (comment) => comment.replace(/[^\n]/g, "")).replace(/(^|[^:"'`])\/\/.*$/gm, "$1");
}

// Words that only look like named colours: i18n keys, ids, enum values.
function isNamedColourFalsePositive(line: string, match: string) {
  const word = match.replace(/^["'`:\s]+/, "");
  return !new RegExp(`(?:color|background|fill|stroke|border|outline|shadow)[\\w-]*["']?\\s*[:=][^;]*\\b${word}\\b`, "i").test(line);
}

/** 1-based line of `index`, by binary search over the line start offsets. */
function lineAt(lineStarts: number[], index: number) {
  let low = 0;
  let high = lineStarts.length - 1;
  while (low < high) {
    const middle = (low + high + 1) >> 1;
    if (lineStarts[middle]! <= index) low = middle;
    else high = middle - 1;
  }
  return low + 1;
}

function lineStartsOf(source: string) {
  const starts = [0];
  for (let index = source.indexOf("\n"); index !== -1; index = source.indexOf("\n", index + 1)) starts.push(index + 1);
  return starts;
}

function colourOffences(path: string, source: string): string[] {
  const code = withoutComments(source);
  const offences: { index: number; text: string }[] = [];
  let lineStarts: number[] | undefined;
  for (const rule of RULES) {
    for (const match of code.matchAll(rule.pattern)) {
      lineStarts ??= lineStartsOf(code);
      const line = lineAt(lineStarts, match.index);
      if (rule.name === "named colour") {
        const lineText = code.slice(lineStarts[line - 1], lineStarts[line] ?? code.length).replace(/\n$/, "");
        if (isNamedColourFalsePositive(lineText, match[0])) continue;
      }
      offences.push({ index: match.index, text: `${path}:${line} ${rule.name} ${match[0].trim()}` });
    }
  }
  return offences.sort((a, b) => a.index - b.index).map(({ text }) => text);
}

describe("theme guard", () => {
  let files: { path: string; source: string }[] = [];

  beforeAll(() => {
    files = sourceFiles(SOURCE_ROOT).map((file) => ({ path: relative(SOURCE_ROOT, file), source: readFileSync(file, "utf8") }));
  }, TREE_SCAN_TIMEOUT_MS);

  it("scans the web sources", () => {
    expect(files.length).toBeGreaterThan(100);
  });

  it("finds no colour literal outside src/lib/theme.ts", () => {
    expect(files.flatMap(({ path, source }) => colourOffences(path, source))).toEqual([]);
  }, TREE_SCAN_TIMEOUT_MS);

  it("still catches every kind of colour literal", () => {
    const sample = [
      'const a = "#ff0000";',
      "const b = `rgb(${r} 0 0)`;",
      "doc.setTextColor(12, 0, 0);",
      'const c = { color: "white" };',
      '<div className="bg-red-500" />',
      '// a comment may say "#fff" and white',
      'const key = "member.white";',
    ].join("\n");
    expect(colourOffences("x.tsx", sample)).toEqual([
      "x.tsx:1 hex colour #ff0000",
      "x.tsx:2 rgb/hsl colour rgb(${",
      "x.tsx:3 RGB channels setTextColor(1",
      'x.tsx:4 named colour "white',
      "x.tsx:5 Tailwind palette class bg-red-500",
    ]);
  });

  it("uses only CSS variables the theme or a stylesheet defines", () => {
    const themeVariables = new Set(Object.keys(cssVariablesForTheme(APP_THEMES.frost)));
    // The website's palette source declares its `--s-*` tokens.
    const palettes = [...THEME_SOURCES].filter((path) => path !== "lib/theme.ts").map((path) => ({ source: readFileSync(join(SOURCE_ROOT, path), "utf8") }));
    const declared = new Set([...files, ...palettes].flatMap(({ source }) => [...source.matchAll(/["']?(--[\w-]+)["']?\s*:/g)].map((match) => match[1]!)));
    const unknown: string[] = [];
    for (const { path, source } of files) {
      for (const match of source.matchAll(/var\((--[\w-]+[\w])(?=[,)])/g)) {
        const name = match[1]!;
        if (!themeVariables.has(name) && !declared.has(name)) unknown.push(`${path} ${name}`);
      }
    }
    expect(unknown).toEqual([]);
  }, TREE_SCAN_TIMEOUT_MS);
});
