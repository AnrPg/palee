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
 */

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

function messageAt(namespace: string, key: string): unknown {
  let node: unknown = en;
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
      (p): p is ts.PropertyAssignment => ts.isPropertyAssignment(p) && p.name.getText() === "namespace",
    );
    if (!property) return "";
    return ts.isStringLiteralLike(property.initializer) ? property.initializer.text : null;
  }
  return null;
}

function bindsName(name: ts.BindingName, wanted: string): boolean {
  if (ts.isIdentifier(name)) return name.text === wanted;
  return name.elements.some((element) => !ts.isOmittedExpression(element) && bindsName(element.name, wanted));
}

/**
 * Walks outwards from `from` to the nearest scope that declares `name`.
 * Returns the namespace when that declaration is a translator, else null.
 */
function resolveTranslator(name: string, from: ts.Node): string | null {
  for (let scope: ts.Node | undefined = from.parent; scope; scope = scope.parent) {
    if (ts.isFunctionLike(scope) && scope.parameters.some((parameter) => bindsName(parameter.name, name))) return null;
    const statements =
      ts.isBlock(scope) || ts.isSourceFile(scope) || ts.isModuleBlock(scope) || ts.isCaseClause(scope) || ts.isDefaultClause(scope)
        ? scope.statements
        : undefined;
    if (!statements) continue;
    for (const statement of statements) {
      if (ts.isFunctionDeclaration(statement) && statement.name?.text === name) return null;
      if (!ts.isVariableStatement(statement)) continue;
      for (const declaration of statement.declarationList.declarations) {
        if (bindsName(declaration.name, name)) {
          return ts.isIdentifier(declaration.name) ? namespaceOf(declaration.initializer) : null;
        }
      }
    }
  }
  return null;
}

function missingKeys(): string[] {
  const problems: string[] = [];
  for (const file of sourceFiles(srcRoot)) {
    const text = fs.readFileSync(file, "utf8");
    if (!/Translations\(/.test(text)) continue;
    const source = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, file.endsWith(".tsx") ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
    const visit = (node: ts.Node) => {
      if (ts.isCallExpression(node) && node.arguments.length > 0) {
        let callee: ts.Expression = node.expression;
        let method: string | null = null;
        if (ts.isPropertyAccessExpression(callee) && METHODS.has(callee.name.text)) {
          method = callee.name.text;
          callee = callee.expression;
        }
        const [first] = node.arguments;
        if (ts.isIdentifier(callee) && ts.isStringLiteralLike(first)) {
          const namespace = resolveTranslator(callee.text, node);
          if (namespace !== null) {
            const message = messageAt(namespace, first.text);
            const ok = method === "raw" ? message !== undefined : typeof message === "string";
            if (!ok) {
              const { line } = source.getLineAndCharacterOfPosition(node.getStart());
              problems.push(`${path.relative(srcRoot, file)}:${line + 1} ${namespace ? `${namespace}.` : ""}${first.text}`);
            }
          }
        }
      }
      ts.forEachChild(node, visit);
    };
    visit(source);
  }
  return problems;
}

describe("translation keys used in source", () => {
  it("exist in the namespace their translator is bound to", () => {
    expect(missingKeys()).toEqual([]);
  });
});
