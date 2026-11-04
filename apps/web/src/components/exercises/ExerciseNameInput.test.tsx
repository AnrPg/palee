import { act, fireEvent, render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { normalizeExerciseSuggestions } from "@/api/exercise-suggestions";
import { replacementFor, textRunAt } from "@/lib/exercise-text-run";

import { ExerciseNameInput } from "./ExerciseNameInput";
import { ExerciseSuggestingTextarea } from "./ExerciseSuggestingTextarea";

const fetchExerciseSuggestions = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) => (values ? `${key}:${Object.values(values).join(",")}` : key),
}));
vi.mock("@/components/session-provider", () => ({
  useOptionalSession: () => ({ status: "authenticated", tokens: { access_token: "tok" }, currentUser: { id: "u-1" } }),
}));
vi.mock("@/api/organizations", () => ({
  fetchOrganizationMemberships: () => Promise.resolve([{ organization: { id: "org-1", slug: "box" } }]),
}));
vi.mock("@/api/exercise-suggestions", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/api/exercise-suggestions")>();
  return { ...actual, fetchExerciseSuggestions: (...args: unknown[]) => fetchExerciseSuggestions(...args) };
});

const groups = [
  { source: "mine", items: [{ name: "Back Squat", catalog_slug: "back-squat", hint: null, uses_count: 10 }] },
  { source: "box", items: [{ name: "Back Squat (pause)", catalog_slug: null, hint: null, uses_count: 3 }] },
  { source: "palee", items: [{ name: "Front Squat", catalog_slug: "front-squat", hint: "strength", uses_count: 0 }] },
];

function wrapper({ children }: { children: ReactNode }) {
  return <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>{children}</QueryClientProvider>;
}

function NameField({ onChange }: { onChange: (name: string, slug: string | null) => void }) {
  const [value, setValue] = useState("");
  return (
    <ExerciseNameInput
      aria-label="exercise"
      value={value}
      onValueChange={(name, slug) => {
        setValue(name);
        onChange(name, slug);
      }}
    />
  );
}

async function settle() {
  await act(async () => {
    vi.advanceTimersByTime(200);
  });
  await act(async () => {
    await Promise.resolve();
  });
}

beforeEach(() => {
  vi.useFakeTimers({ shouldAdvanceTime: true });
  fetchExerciseSuggestions.mockReset();
  fetchExerciseSuggestions.mockResolvedValue(groups);
});
afterEach(() => vi.useRealTimers());

describe("ExerciseNameInput (ADR-461)", () => {
  it("shows the groups and a keep-as-typed row; a pick links the catalog slug", async () => {
    const onChange = vi.fn();
    render(<NameField onChange={onChange} />, { wrapper });
    const input = screen.getByRole("combobox", { name: "exercise" });
    fireEvent.change(input, { target: { value: "bak sqat" } });
    await settle();

    expect(await screen.findByText("group.mine")).toBeInTheDocument();
    expect(screen.getByText("group.box")).toBeInTheDocument();
    expect(screen.getByText("group.palee")).toBeInTheDocument();
    expect(screen.getByText("keep:bak sqat")).toBeInTheDocument();
    expect(screen.getByText("usesMine:10")).toBeInTheDocument();
    expect(screen.getByText("category.strength")).toBeInTheDocument();
    expect(fetchExerciseSuggestions).toHaveBeenCalledWith("tok", { q: "bak sqat", organizationId: "org-1", limit: undefined }, expect.anything());

    fireEvent.keyDown(input, { key: "Enter" });
    expect(onChange).toHaveBeenLastCalledWith("Back Squat", "back-squat");
    expect(input).toHaveValue("Back Squat");
  });

  it("↓ moves, Esc keeps the typed text, the keep row keeps it with no link", async () => {
    const onChange = vi.fn();
    render(<NameField onChange={onChange} />, { wrapper });
    const input = screen.getByRole("combobox", { name: "exercise" });
    fireEvent.change(input, { target: { value: "squat" } });
    await settle();
    await screen.findByText("group.mine");

    fireEvent.keyDown(input, { key: "Escape" });
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    expect(input).toHaveValue("squat");

    fireEvent.change(input, { target: { value: "squat " } });
    await settle();
    await screen.findByText("group.mine");
    for (let i = 0; i < 3; i += 1) fireEvent.keyDown(input, { key: "ArrowDown" });
    fireEvent.keyDown(input, { key: "Enter" });
    expect(onChange).toHaveBeenLastCalledWith("squat ", null);
  });

  it("tolerates a malformed answer", async () => {
    fetchExerciseSuggestions.mockResolvedValue(normalizeExerciseSuggestions({}));
    render(<NameField onChange={vi.fn()} />, { wrapper });
    fireEvent.change(screen.getByRole("combobox", { name: "exercise" }), { target: { value: "row" } });
    await settle();
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    expect(normalizeExerciseSuggestions({ groups: [{ source: "mine", items: [{ name: 3 }, { name: "Row" }] }, "x"] })).toEqual([
      { source: "mine", items: [{ name: "Row", catalog_slug: null, hint: null, uses_count: 0 }] },
    ]);
  });
});

describe("text runs in a note", () => {
  it("takes the words just typed, stops at numbers and punctuation, keeps T2B", () => {
    expect(textRunAt("Did 5x5 back sq", 15)).toMatchObject({ from: 8, query: "back sq" });
    expect(textRunAt("Felt good. T2B", 14)).toMatchObject({ query: "T2B" });
    expect(textRunAt("back sq then", 6)).toBeNull();
    expect(textRunAt("ok ", 3)).toBeNull();
    const run = textRunAt("today did back sq", 17)!;
    expect(replacementFor(run, "Back Squat")).toEqual({ from: 10, exact: false });
    expect(replacementFor(textRunAt("Back Squat", 10)!, "Back Squat")).toEqual({ from: 0, exact: true });
  });
});

describe("ExerciseSuggestingTextarea (ADR-461)", () => {
  function Note({ onChange }: { onChange: (text: string) => void }) {
    const [value, setValue] = useState("");
    return (
      <ExerciseSuggestingTextarea
        aria-label="note"
        value={value}
        onValueChange={(text) => {
          setValue(text);
          onChange(text);
        }}
      />
    );
  }

  function type(textarea: HTMLTextAreaElement, text: string) {
    fireEvent.change(textarea, { target: { value: text } });
    textarea.setSelectionRange(text.length, text.length);
    fireEvent.select(textarea);
  }

  it("offers names at the caret only while the words match; Enter replaces them", async () => {
    const onChange = vi.fn();
    render(<Note onChange={onChange} />, { wrapper });
    const textarea = screen.getByRole("textbox", { name: "note" }) as HTMLTextAreaElement;

    type(textarea, "today 5x5 back sq");
    await settle();
    expect(await screen.findByTestId("exercise-text-suggestions")).toBeInTheDocument();
    fireEvent.keyDown(textarea, { key: "Enter" });
    expect(onChange).toHaveBeenLastCalledWith("today 5x5 Back Squat");
  });

  it("never takes Enter when no list is open, and Esc closes the list", async () => {
    fetchExerciseSuggestions.mockResolvedValue([]);
    render(<Note onChange={vi.fn()} />, { wrapper });
    const textarea = screen.getByRole("textbox", { name: "note" }) as HTMLTextAreaElement;
    type(textarea, "felt strong");
    await settle();
    expect(screen.queryByTestId("exercise-text-suggestions")).not.toBeInTheDocument();
    const enter = fireEvent.keyDown(textarea, { key: "Enter" });
    expect(enter).toBe(true);

    fetchExerciseSuggestions.mockResolvedValue(groups);
    type(textarea, "felt strong back squ");
    await settle();
    expect(await screen.findByTestId("exercise-text-suggestions")).toBeInTheDocument();
    fireEvent.keyDown(textarea, { key: "Escape" });
    expect(screen.queryByTestId("exercise-text-suggestions")).not.toBeInTheDocument();
  });
});
