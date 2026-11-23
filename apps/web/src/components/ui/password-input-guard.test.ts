import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import { describe, expect, it } from "vitest";

/**
 * Password reveal guard (2026-11-22): every masked field lets the person see
 * what they typed. Screens use ui/PasswordInput (or ui/MaskableInput, or
 * auth/AuthField with type "password"), never a raw `<input type="password">`.
 */

const SOURCE_ROOT = join(__dirname, "..", "..");
const ALLOWED = new Set(["components/ui/PasswordInput.tsx"]);

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    if (statSync(path).isDirectory())
      return relative(SOURCE_ROOT, path) === "api/generated"
        ? []
        : sourceFiles(path);
    if (!entry.endsWith(".tsx") || entry.includes(".test.")) return [];
    return [path];
  });
}

describe("password reveal guard", () => {
  it("masks secrets only through ui/PasswordInput", () => {
    const findings: string[] = [];
    for (const path of sourceFiles(SOURCE_ROOT)) {
      const name = relative(SOURCE_ROOT, path);
      if (ALLOWED.has(name)) continue;
      const source = readFileSync(path, "utf8");
      for (const tag of source.match(/<input\b[^]*?\/>/g) ?? []) {
        if (/\btype=(?:"password"|\{[^}]*"password")/.test(tag))
          findings.push(`${name}: ${tag.replace(/\s+/g, " ").slice(0, 80)}`);
      }
    }
    expect(findings).toEqual([]);
    // A walk over the whole source tree: its own budget, so a busy CI runner never times it out.
  }, 30_000);
});
