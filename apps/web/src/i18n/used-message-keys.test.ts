// @vitest-environment node
import fs from "node:fs";
import path from "node:path";
import ts from "typescript";
import { describe, expect, it } from "vitest";

/**
 * Guard: every literal key a component asks a translator for must exist in
 * the namespace that translator is bound to. next-intl does not fail on a
 * missing key; it shows the raw path to the user (for example
 * «Ui.forgotPasswordLink» under the purge password field). Locale parity is
 * checked by scripts/validate-messages.mjs, so English is the reference here.
 *
 * Each call `t("key")`, `t.rich("key")`, `t.markup("key")` or `t.raw("key")`
 * is resolved lexically to the nearest declaration of `t`:
 *   const t = useTranslations("NS") / await getTranslations("NS")
 *   const t = await getTranslations({ locale, namespace: "NS" })
 *   const t = useUiTranslations() / await getUiTranslations()   -> "Ui"
 * A translator received as a parameter or prop, dynamic keys and `t.has`
 * are out of reach and skipped.
 *
 * The scan parses every source file that creates a translator, so its cost
 * grows with the code. It runs in one walk per file: scopes are kept on a
 * stack while descending (no parent pointers, no walk back up per call), a
 * scope's bindings are collected once and only when a call looks a name up,
 * JSDoc is not parsed, and the test needs no DOM. It also has its own
 * timeout, well above what a slow, fully loaded CI runner needs.
 */

const TREE_SCAN_TIMEOUT_MS = 60_000;

const srcRoot = path.resolve(__dirname, "..");
const en = JSON.parse(fs.readFileSync(path.resolve(__dirname, "../../messages/en.json"), "utf8")) as Record<string, unknown>;

const UI_HELPERS = new Set(["useUiTranslations", "getUiTranslations"]);
const NEXT_INTL = new Set(["useTranslations", "getTranslations"]);
const METHODS = new Set(["rich", "markup", "raw"]);

function sourceFiles(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return entry.name === "generated" ? [] : sourceFiles(full);
    return /\.tsx?$/.test(entry.name) && !/\.test\.tsx?$/.test(entry.name) ? [full] : [];
  });
}

function messageAt(messages: Record<string, unknown>, namespace: string, key: string): unknown {
  let node: unknown = messages;
  for (const part of [...(namespace ? namespace.split(".") : []), ...key.split(".")]) {
    if (!node || typeof node !== "object" || !Object.hasOwn(node, part)) return undefined;
    node = (node as Record<string, unknown>)[part];
  }
  return node;
}

/** The namespace a translator initializer binds, or null when it is not one. */
function namespaceOf(initializer: ts.Expression | undefined): string | null {
  let expression = initializer;
  while (expression && (ts.isAwaitExpression(expression) || ts.isParenthesizedExpression(expression))) {
    expression = expression.expression;
  }
  if (!expression || !ts.isCallExpression(expression) || !ts.isIdentifier(expression.expression)) return null;
  const callee = expression.expression.text;
  if (UI_HELPERS.has(callee)) return "Ui";
  if (!NEXT_INTL.has(callee)) return null;
  const [argument] = expression.arguments;
  if (!argument) return "";
  if (ts.isStringLiteralLike(argument)) return argument.text;
  if (ts.isObjectLiteralExpression(argument)) {
    const property = argument.properties.find(
      (p): p is ts.PropertyAssignment =>
        ts.isPropertyAssignment(p) && (ts.isIdentifier(p.name) || ts.isStringLiteral(p.name)) && p.name.text === "namespace",
    );
    if (!property) return "";
    return ts.isStringLiteralLike(property.initializer) ? property.initializer.text : null;
  }
  return null;
}

function boundNames(name: ts.BindingName, into: string[] = []): string[] {
  if (ts.isIdentifier(name)) into.push(name.text);
  else for (const element of name.elements) if (!ts.isOmittedExpression(element)) boundNames(element.name, into);
  return into;
}

/**
 * What one scope binds: name -> translator namespace, or null when the name
 * is bound to something that is not a translator (it shadows outer ones).
 * The first declaration of a name in a scope wins.
 */
type Bindings = Map<string, string | null>;

function bindingsOf(scope: ts.Node): Bindings {
  const bindings: Bindings = new Map();
  const bind = (name: string, namespace: string | null) => {
    if (!bindings.has(name)) bindings.set(name, namespace);
  };
  if (ts.isFunctionLike(scope)) {
    for (const parameter of scope.parameters) for (const name of boundNames(parameter.name)) bind(name, null);
    return bindings;
  }
  for (const statement of (scope as ts.Block).statements) {
    if (ts.isFunctionDeclaration(statement) && statement.name) bind(statement.name.text, null);
    if (!ts.isVariableStatement(statement)) continue;
    for (const declaration of statement.declarationList.declarations) {
      const namespace = ts.isIdentifier(declaration.name) ? namespaceOf(declaration.initializer) : null;
      for (const name of boundNames(declaration.name)) bind(name, namespace);
    }
  }
  return bindings;
}

/**
 * Syntax kinds that open a scope: a list of statements, or a function's
 * parameters (every kind `ts.isFunctionLike` accepts, so a new TypeScript
 * release keeps the same answer). Checked once per node, so a table.
 */
const SCOPE_KINDS: ReadonlySet<ts.SyntaxKind> = new Set([
  ts.SyntaxKind.Block,
  ts.SyntaxKind.SourceFile,
  ts.SyntaxKind.ModuleBlock,
  ts.SyntaxKind.CaseClause,
  ts.SyntaxKind.DefaultClause,
  ...Object.values(ts.SyntaxKind)
    .filter((kind): kind is ts.SyntaxKind => typeof kind === "number")
    .filter((kind) => ts.isFunctionLike({ kind } as ts.Node)),
]);

/** Subtrees that hold no runtime call (types, imports), so the walk never enters them. */
const SKIPPED_KINDS: ReadonlySet<ts.SyntaxKind> = new Set([
  ts.SyntaxKind.ImportDeclaration,
  ts.SyntaxKind.InterfaceDeclaration,
  ts.SyntaxKind.TypeAliasDeclaration,
]);

/** Every literal key in `text` that is missing from the namespace its translator is bound to. */
function missingKeysIn(relativePath: string, text: string, messages: Record<string, unknown>): string[] {
  const source = ts.createSourceFile(
    relativePath,
    text,
    { languageVersion: ts.ScriptTarget.Latest, jsDocParsingMode: ts.JSDocParsingMode.ParseNone },
    false,
    relativePath.endsWith(".tsx") ? ts.ScriptKind.TSX : ts.ScriptKind.TS,
  );
  const problems: string[] = [];
  // Innermost scope last; bindings are filled in on the first lookup that reaches the scope.
  const scopes: { node: ts.Node; bindings?: Bindings }[] = [];

  const resolveTranslator = (name: string): string | null => {
    for (let index = scopes.length - 1; index >= 0; index--) {
      const scope = scopes[index]!;
      scope.bindings ??= bindingsOf(scope.node);
      const namespace = scope.bindings.get(name);
      if (namespace !== undefined) return namespace;
    }
    return null;
  };

  const check = (node: ts.CallExpression) => {
    let callee: ts.Expression = node.expression;
    let method: string | null = null;
    if (ts.isPropertyAccessExpression(callee) && METHODS.has(callee.name.text)) {
      method = callee.name.text;
      callee = callee.expression;
    }
    const [first] = node.arguments;
    if (!first || !ts.isIdentifier(callee) || !ts.isStringLiteralLike(first)) return;
    const namespace = resolveTranslator(callee.text);
    if (namespace === null) return;
    const message = messageAt(messages, namespace, first.text);
    const ok = method === "raw" ? message !== undefined : typeof message === "string";
    if (ok) return;
    const { line } = source.getLineAndCharacterOfPosition(node.getStart(source));
    problems.push(`${relativePath}:${line + 1} ${namespace ? `${namespace}.` : ""}${first.text}`);
  };

  const visit = (node: ts.Node): void => {
    if (SKIPPED_KINDS.has(node.kind) || (node.kind >= ts.SyntaxKind.FirstTypeNode && node.kind <= ts.SyntaxKind.LastTypeNode)) return;
    const scoped = SCOPE_KINDS.has(node.kind);
    if (scoped) scopes.push({ node });
    if (node.kind === ts.SyntaxKind.CallExpression) check(node as ts.CallExpression);
    ts.forEachChild(node, visit);
    if (scoped) scopes.pop();
  };
  visit(source);
  return problems;
}

describe("translation keys used in source", () => {
  it(
    "exist in the namespace their translator is bound to",
    () => {
      const files = sourceFiles(srcRoot);
      expect(files.length).toBeGreaterThan(100);
      const problems = files.flatMap((file) => {
        const text = fs.readFileSync(file, "utf8");
        return /Translations\(/.test(text) ? missingKeysIn(path.relative(srcRoot, file), text, en) : [];
      });
      expect(problems).toEqual([]);
    },
    TREE_SCAN_TIMEOUT_MS,
  );

  it("still resolves each translator to its nearest declaration", () => {
    const messages = { A: { ok: "x", nested: { deep: "y" }, obj: { k: "v" } }, Ui: { save: "Save" }, top: "z" };
    const sample = [
      'const t = useTranslations("A");',
      't("ok"); t("missing"); t.rich("nested.deep"); t.markup("nested"); t.raw("obj");',
      "function inner() {",
      "  const t = useUiTranslations();",
      '  t("save"); t("ok");',
      "}",
      "async function server(locale: string) {",
      '  const t = await getTranslations({ locale, namespace: "A" });',
      '  t("gone");',
      "}",
      'function prop(t: (key: string) => string) { t("whatever"); }',
      'function local() { const { t } = props; t("whatever"); const u = makeT(); u("whatever"); }',
      'function root() { const t = useTranslations(); t("top"); t("A.ok"); t("nope"); }',
      'const v = useTranslations("A"); function hoisted() { v("late"); }',
    ].join("\n");
    expect(missingKeysIn("x.tsx", sample, messages)).toEqual([
      "x.tsx:2 A.missing",
      "x.tsx:2 A.nested",
      "x.tsx:5 Ui.ok",
      "x.tsx:9 A.gone",
      "x.tsx:13 nope",
      "x.tsx:14 A.late",
    ]);
  });
});
