import { getSchema, type AnyExtension, type JSONContent } from "@tiptap/core";
import { Node as PmNode } from "@tiptap/pm/model";
import { EditorState } from "@tiptap/pm/state";
import Underline from "@tiptap/extension-underline";
import StarterKit from "@tiptap/starter-kit";

import { applyExerciseLinks, ExerciseLink, type LinkSpan } from "./exercise-link";

/**
 * ADR-180 / ADR-671: the content extensions of one section's text editor
 * (what its document may hold). The section editor adds its behaviour
 * extensions (placeholder, suggestion keys) on top; `linkSectionDocument`
 * builds the same schema to put the coach's answers into a section's saved
 * document without its editor.
 */
export function sectionContentExtensions(): AnyExtension[] {
  return [StarterKit.configure({ link: false, underline: false, heading: { levels: [3, 4] } }), Underline, ExerciseLink];
}

let schema: ReturnType<typeof getSchema> | null = null;

/**
 * ADR-671: a section's document with the coach's answers to the exercise
 * check as `exerciseLink` marks (`applyExerciseLinks`, the same placing the
 * free-text editor uses). A document the schema cannot read comes back as it was.
 */
export function linkSectionDocument(document: JSONContent, spans: LinkSpan[]): { document: JSONContent; applied: number } {
  if (spans.length === 0) return { document, applied: 0 };
  schema ??= getSchema(sectionContentExtensions());
  let doc: PmNode;
  try {
    doc = PmNode.fromJSON(schema, document);
  } catch {
    return { document, applied: 0 };
  }
  const { tr, applied } = applyExerciseLinks(EditorState.create({ schema, doc }), spans);
  return { document: tr.docChanged ? (tr.doc.toJSON() as JSONContent) : document, applied };
}
