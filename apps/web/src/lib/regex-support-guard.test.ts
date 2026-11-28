import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import ts from "typescript";
import { describe, expect, it } from "vitest";

/**
 * Regex guard (2026-11-28): no lookbehind (`(?<=` / `(?<!`) in app code.
 * WebKit before 16.4 (every browser on an older iPhone, Chrome included)
 * cannot even parse a regex literal with one: the whole script chunk fails,
 * the page never hydrates, and the person is left on the sign-in splash.
 * Build tools do not rewrite regex syntax, so the guard is here.
 */

const SOURCE_ROOT = join(__dirname, "..");
const SKIPPED_DIRECTORIES = new Set(["api/generated"]);
const LOOKBEHIND = /\(\?<[=!]/;

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    const relativePath = relative(SOURCE_ROOT, path);
    if (statSync(path).isDirectory()) return SKIPPED_DIRECTORIES.has(relativePath) ? [] : sourceFiles(path);
    if (!/\.tsx?$/.test(entry) || entry.includes(".test.") || entry.endsWith(".d.ts")) return [];
    return [path];
  });
}

function lookbehinds(path: string): string[] {
  const text = readFileSync(path, "utf8");
  if (!LOOKBEHIND.test(text)) return [];
  const source = ts.createSourceFile(path, text, ts.ScriptTarget.Latest, true);
  const found: string[] = [];
  const report = (node: ts.Node) => {
    const { line } = source.getLineAndCharacterOfPosition(node.getStart());
    found.push(`${relative(SOURCE_ROOT, path)}:${line + 1}`);
  };
  const visit = (node: ts.Node) => {
    if (ts.isRegularExpressionLiteral(node) && LOOKBEHIND.test(node.text)) report(node);
    if (
      (ts.isNewExpression(node) || ts.isCallExpression(node)) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === "RegExp"
    ) {
      const pattern = node.arguments?.[0];
      if (pattern && ts.isStringLiteralLike(pattern) && LOOKBEHIND.test(pattern.text)) report(node);
    }
    ts.forEachChild(node, visit);
  };
  visit(source);
  return found;
}

describe("regex support guard", () => {
  it("uses no regex lookbehind, which older iPhones cannot parse", { timeout: 60_000 }, () => {
    expect(sourceFiles(SOURCE_ROOT).flatMap(lookbehinds)).toEqual([]);
  });
});
