import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { EditorContent, useEditor, type Editor } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import { NextIntlClientProvider } from "next-intl";
import { useEffect } from "react";
import { describe, expect, it, vi } from "vitest";

import el from "../../../../messages/el.json";

const catalog = vi.hoisted(() => [
  { source: "palee", items: [{ name: "Back Squat", catalog_slug: "back-squat", hint: null, uses_count: 0 }] },
]);
vi.mock("@/hooks/useExerciseSuggestions", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/hooks/useExerciseSuggestions")>()),
  useExerciseSuggestions: (text: string) => ({ groups: text.length >= 2 ? catalog : [], isFetching: false }),
}));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));

import { useEditorExerciseSuggestions, useExerciseSuggestKeys } from "./EditorExerciseSuggestions";
import { ExerciseLink, ExerciseSuggestKeys } from "./exercise-link";
import { SectionTextEditor } from "./SectionedWorkoutEditor";

let freeText: Editor | null = null;
function FreeTextHost() {
  const keys = useExerciseSuggestKeys();
  const editor = useEditor({
    extensions: [StarterKit, ExerciseLink, ExerciseSuggestKeys.configure({ onKeyDown: keys.onKeyDown })],
    content: "<p></p>",
    immediatelyRender: false,
  });
  useEffect(() => {
    freeText = editor;
  }, [editor]);
  const { menu } = useEditorExerciseSuggestions(editor, keys.handlerRef);
  return (
    <>
      <EditorContent editor={editor} />
      {menu}
    </>
  );
}

function withIntl(node: React.ReactNode) {
  return (
    <NextIntlClientProvider locale="el" messages={el}>
      {node}
    </NextIntlClientProvider>
  );
}

/** jsdom lays nothing out, so the list's position is faked. */
function fakeLayout(editor: Editor) {
  vi.spyOn(editor.view, "coordsAtPos").mockReturnValue({ top: 0, bottom: 10, left: 0, right: 0 });
}

describe("exercise suggestions in the WOD text editors (ADR-570)", () => {
  it("opens the list in the free-text editor and Tab links the picked name", async () => {
    render(withIntl(<FreeTextHost />));
    await waitFor(() => expect(freeText).toBeTruthy());
    const editor = freeText!;
    fakeLayout(editor);
    act(() => {
      editor.chain().focus().insertContent("5x5 back sq").run();
    });
    expect(await screen.findByTestId("editor-exercise-suggestions")).toHaveTextContent("Back Squat");
    fireEvent.keyDown(editor.view.dom, { key: "Tab" });
    expect(editor.getText()).toBe("5x5 Back Squat");
    expect(JSON.stringify(editor.getJSON())).toContain('"ref":"back-squat"');
  });

  it("takes Enter only after the arrows, and Esc hides the list", async () => {
    render(withIntl(<FreeTextHost />));
    await waitFor(() => expect(freeText).toBeTruthy());
    const editor = freeText!;
    fakeLayout(editor);
    act(() => {
      editor.chain().focus().insertContent("back sq").run();
    });
    await screen.findByTestId("editor-exercise-suggestions");
    fireEvent.keyDown(editor.view.dom, { key: "ArrowDown" });
    fireEvent.keyDown(editor.view.dom, { key: "Enter" });
    expect(editor.getText()).toBe("Back Squat");

    act(() => {
      editor.chain().focus().insertContent(", back sq").run();
    });
    await screen.findByTestId("editor-exercise-suggestions");
    fireEvent.keyDown(editor.view.dom, { key: "Escape" });
    await waitFor(() => expect(screen.queryByTestId("editor-exercise-suggestions")).toBeNull());
  });

  it("opens the same list in a text section (WOD assistant off), the picked name plain text", async () => {
    const onChange = vi.fn();
    const { container } = render(withIntl(<SectionTextEditor document={{ type: "doc", content: [] }} label="Τμήμα" onChange={onChange} />));
    await waitFor(() => expect(container.querySelector(".ProseMirror")).toBeTruthy());
    const dom = container.querySelector(".ProseMirror") as HTMLElement & { editor?: Editor };
    const editor = dom.editor!;
    fakeLayout(editor);
    act(() => {
      editor.chain().focus().insertContent("back sq").run();
    });
    expect(await screen.findByTestId("editor-exercise-suggestions")).toHaveTextContent("Back Squat");
    fireEvent.keyDown(editor.view.dom, { key: "Tab" });
    expect(editor.getText()).toBe("Back Squat");
    expect(onChange).toHaveBeenLastCalledWith("Back Squat", expect.anything());
    expect(JSON.stringify(editor.getJSON())).not.toContain("exerciseLink");
  });
});
