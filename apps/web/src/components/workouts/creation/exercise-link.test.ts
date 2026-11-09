import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import { afterEach, describe, expect, it } from "vitest";

import type { ExerciseMatch } from "@/api/exercise-matches";
import type { ExerciseSuggestionGroup } from "@/api/exercise-suggestions";
import { allAnswered, groupExerciseMatches, initialAnswers, linkFor, matchDecisions } from "@/lib/exercise-match-answers";
import { textRunAt } from "@/lib/exercise-text-run";

import { caretOf, ghostFor, suggestionsFor } from "./EditorExerciseSuggestions";
import { applyExerciseLinks, EXERCISE_LINK, ExerciseLink, ExerciseSuggestKeys, exerciseGhostKey } from "./exercise-link";

let editor: Editor | null = null;
afterEach(() => editor?.destroy());

function makeEditor(content: string) {
  editor = new Editor({ extensions: [StarterKit, ExerciseLink, ExerciseSuggestKeys], content });
  return editor;
}

/** The linked runs of the document: `[text, ref]`. */
function links(e: Editor) {
  const out: [string, string | null][] = [];
  e.state.doc.descendants((node) => {
    if (!node.isText) return true;
    const mark = node.marks.find((m) => m.type.name === EXERCISE_LINK);
    if (mark) {
      const last = out[out.length - 1];
      if (last && last[1] === mark.attrs.ref) last[0] += node.text;
      else out.push([node.text ?? "", mark.attrs.ref as string | null]);
    }
    return false;
  });
  return out;
}

const match = (extra: Partial<ExerciseMatch>): ExerciseMatch => ({
  id: "0:0:9",
  line: 0,
  from: 0,
  to: 9,
  typed: "Thrusters",
  folded: "thrusters",
  exercise_ref: "thruster",
  label: "Thruster",
  kind: "exact",
  remembered: false,
  muscles: [{ id: "quadriceps", role: "primary" }],
  qualities: [],
  ...extra,
});

describe("exercise links in the free-text editor (ADR-570)", () => {
  it("keeps a link while its words are edited and drops it only with them", () => {
    const e = makeEditor("<p>21 Thrusters</p>");
    e.view.dispatch(e.state.tr.addMark(4, 13, e.schema.marks[EXERCISE_LINK]!.create({ ref: "thruster" })));
    expect(links(e)).toEqual([["Thrusters", "thruster"]]);

    // Letters typed right after the link join it; a space ends it.
    e.commands.insertContentAt(13, "x");
    expect(links(e)).toEqual([["Thrustersx", "thruster"]]);
    e.commands.insertContentAt(14, " and");
    expect(links(e)).toEqual([["Thrustersx", "thruster"]]);

    // Deleting most of the word keeps the link; deleting all of it removes it.
    e.commands.deleteRange({ from: 5, to: 14 });
    expect(links(e)).toEqual([["T", "thruster"]]);
    e.commands.deleteRange({ from: 4, to: 5 });
    expect(links(e)).toEqual([]);
  });

  it("renders a rejected match orange-red, never struck through", () => {
    const e = makeEditor("<p>Run 400m</p>");
    e.view.dispatch(e.state.tr.addMark(1, 4, e.schema.marks[EXERCISE_LINK]!.create({ ref: null })));
    expect(e.getHTML()).toContain('class="exercise-link exercise-link-rejected"');
    expect(e.getHTML()).not.toContain("<s>");
  });

  it("puts the answers into the document by line and offset, finding moved words", () => {
    const e = makeEditor("<p>AMRAP 12</p><p>10 Thrusters</p><p>10 pull ups<br>Run</p>");
    const { tr, applied } = applyExerciseLinks(e.state, [
      { line: 1, from: 3, to: 12, typed: "Thrusters", ref: "thruster", checked: null },
      // The words moved by one character since the check.
      { line: 2, from: 2, to: 10, typed: "pull ups", ref: "pull-up", checked: null },
      // After the hard break, which counts as one character.
      { line: 2, from: 12, to: 15, typed: "Run", ref: null, checked: null },
      { line: 7, from: 0, to: 3, typed: "Row", ref: "row", checked: null },
    ]);
    e.view.dispatch(tr);
    expect(applied).toBe(3);
    expect(links(e)).toEqual([
      ["Thrusters", "thruster"],
      ["pull ups", "pull-up"],
      ["Run", null],
    ]);
    expect(e.getJSON().content?.[1]?.content?.[1]?.marks).toEqual([
      { type: EXERCISE_LINK, attrs: { ref: "thruster", checked: null } },
    ]);
  });

  it("reads the run before the caret and shows the ghost the list asks for", () => {
    const e = makeEditor("<p>21 thru</p>");
    e.commands.setTextSelection(8);
    const caret = caretOf(e)!;
    expect(caret.run.query).toBe("thru");
    expect(caret.blockStart + caret.run.from).toBe(4);

    e.view.dispatch(e.state.tr.setMeta(exerciseGhostKey, { pos: 8, text: "sters" }));
    expect(e.view.dom.querySelector('[data-testid="exercise-ghost"]')?.textContent).toBe("sters");
    e.commands.insertContentAt(8, "s");
    expect(e.view.dom.querySelector('[data-testid="exercise-ghost"]')).toBeNull();
  });
});

describe("suggestions at the caret (ADR-570)", () => {
  const groups: ExerciseSuggestionGroup[] = [
    { source: "mine", items: [{ name: "Thruster complex", catalog_slug: null, hint: null, uses_count: 3 }] },
    { source: "box", items: [{ name: "thruster", catalog_slug: "thruster", hint: null, uses_count: 2 }] },
    { source: "palee", items: [{ name: "Thruster", catalog_slug: "thruster", hint: null, uses_count: 0 }] },
  ];

  it("offers Palee's names first, then the box's and mine, once each", () => {
    const text = "21 thru";
    const items = suggestionsFor(textRunAt(text, text.length)!, text, groups);
    expect(items.map((item) => [item.name, item.source, item.ref])).toEqual([
      ["Thruster", "palee", "thruster"],
      ["Thruster complex", "mine", null],
    ]);
    expect(items[0]!.from).toBe(3);
  });

  it("offers nothing once the words already are a name", () => {
    const text = "21 Thruster";
    expect(suggestionsFor(textRunAt(text, text.length)!, text, groups)).toEqual([]);
  });

  it("shows the rest of a name that continues the typed words, nothing otherwise", () => {
    expect(ghostFor("thru", "Thruster")).toBe("ster");
    expect(ghostFor("θρα", "Θραστερ")).toBe("στερ");
    expect(ghostFor("trusters", "Thruster")).toBeNull();
    expect(ghostFor("Thruster", "Thruster")).toBeNull();
  });
});

describe("answers to the found exercises (ADR-570)", () => {
  const matches = [
    match({ id: "1:3:12", line: 1 }),
    match({ id: "4:3:12", line: 4, remembered: true }),
    match({ id: "2:0:6", line: 2, typed: "pulups", folded: "pulups", exercise_ref: "pull-up", label: "Pull-up", kind: "fuzzy", remembered: true }),
    match({ id: "3:0:4", line: 3, typed: "Rowe", folded: "rowe", exercise_ref: "row", label: "Row", kind: "changed" }),
  ];

  it("asks once for the same words and exercise, a remembered one already «Ναι»", () => {
    const groups = groupExerciseMatches(matches);
    expect(groups.map((group) => [group.typed, group.matches.length, group.remembered])).toEqual([
      ["Thrusters", 2, false],
      ["pulups", 1, true],
      ["Rowe", 1, false],
    ]);
    const answers = initialAnswers(groups);
    expect(answers).toEqual({ [groups[1]!.key]: "yes" });
    expect(allAnswered(groups, answers)).toBe(false);
    const all = { ...answers, [groups[0]!.key]: "no" as const, [groups[2]!.key]: "yes" as const };
    expect(allAnswered(groups, all)).toBe(true);
    expect(matchDecisions(groups, all)).toEqual([
      { typed: "Thrusters", exercise_ref: "thruster", decision: "no" },
      { typed: "pulups", exercise_ref: "pull-up", decision: "yes" },
      { typed: "Rowe", exercise_ref: "row", decision: "yes" },
    ]);
  });

  it("links a «Ναι», keeps a «Όχι» plain, confirms a changed link's words", () => {
    expect(linkFor(matches[0]!, "yes")).toEqual({ ref: "thruster", checked: null });
    expect(linkFor(matches[0]!, "no")).toEqual({ ref: null, checked: null });
    expect(linkFor(matches[3]!, "yes")).toEqual({ ref: "row", checked: "rowe" });
  });
});
