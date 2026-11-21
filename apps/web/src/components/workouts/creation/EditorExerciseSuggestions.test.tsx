import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
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
const FORMATS = { formats: { frequent: [{ format: "amrap", duration_seconds: 720 } as const] } };
function FreeTextHost({ formats = false }: { formats?: boolean }) {
  const keys = useExerciseSuggestKeys();
  const editor = useEditor({
    extensions: [StarterKit, ExerciseLink, ExerciseSuggestKeys.configure({ onKeyDown: keys.onKeyDown })],
    content: "<p></p>",
    immediatelyRender: false,
  });
  useEffect(() => {
    freeText = editor;
  }, [editor]);
  const { menu } = useEditorExerciseSuggestions(editor, keys.handlerRef, formats ? FORMATS : undefined);
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

  it("offers WOD formats at the start of a line, the coach's most used first (ADR-650)", async () => {
    render(withIntl(<FreeTextHost formats />));
    await waitFor(() => expect(freeText).toBeTruthy());
    const editor = freeText!;
    fakeLayout(editor);
    act(() => {
      editor.chain().focus().insertContent("am").run();
    });
    const list = await screen.findByTestId("editor-exercise-suggestions");
    const options = within(list).getAllByRole("option");
    expect(options.map((option) => option.textContent)).toEqual(["AMRAP 12Μορφή · συχνό σου", "AMRAP Μορφή"]);
    fireEvent.keyDown(editor.view.dom, { key: "Tab" });
    expect(editor.getText()).toBe("AMRAP 12");
    expect(JSON.stringify(editor.getJSON())).not.toContain("exerciseLink");
  });

  it("offers no formats in the middle of an exercise line", async () => {
    render(withIntl(<FreeTextHost formats />));
    await waitFor(() => expect(freeText).toBeTruthy());
    const editor = freeText!;
    fakeLayout(editor);
    act(() => {
      editor.chain().focus().insertContent("10 burpees then 5 back sq").run();
    });
    const list = await screen.findByTestId("editor-exercise-suggestions");
    expect(within(list).queryByText("Μορφή")).toBeNull();
    expect(within(list).queryByTestId("editor-suggestions-format-help")).toBeNull();
  });

  it("opens the formats help from the list while formats are offered (ADR-650)", async () => {
    render(withIntl(<FreeTextHost formats />));
    await waitFor(() => expect(freeText).toBeTruthy());
    const editor = freeText!;
    fakeLayout(editor);
    act(() => {
      editor.chain().focus().insertContent("em").run();
    });
    const list = await screen.findByTestId("editor-exercise-suggestions");
    fireEvent.click(within(list).getByTestId("editor-suggestions-format-help"));
    expect(await screen.findByTestId("wod-formats-help")).toHaveTextContent("Χρονόμετρο από αυτό που γράφεις");
  });

  it("opens the same list in a text section (WOD assistant off) and links the picked name (ADR-671)", async () => {
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
    expect(JSON.stringify(editor.getJSON())).toContain('"ref":"back-squat"');
  });

  it("always opens right under the line being written, even near the bottom of the screen", async () => {
    render(withIntl(<FreeTextHost />));
    await waitFor(() => expect(freeText).toBeTruthy());
    const editor = freeText!;
    const lineBottom = window.innerHeight - 20;
    vi.spyOn(editor.view, "coordsAtPos").mockReturnValue({ top: lineBottom - 18, bottom: lineBottom, left: 40, right: 40 });
    act(() => {
      editor.chain().focus().insertContent("back sq").run();
    });
    const list = await screen.findByTestId("editor-exercise-suggestions");
    await waitFor(() => expect(list.style.visibility).toBe("visible"));
    expect(list.style.top).toBe(`${lineBottom + 4}px`);
    // Short room below: the list scrolls inside instead of jumping above the line.
    expect(list.style.maxHeight).toBe("120px");
    expect(list.style.overflowY).toBe("auto");
  });
});
