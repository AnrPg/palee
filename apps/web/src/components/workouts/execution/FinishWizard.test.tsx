import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { FinishWizard } from "./FinishWizard";

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

// The note suggests exercise names (ADR-461); these tests type no names.
vi.mock("@/hooks/useExerciseSuggestions", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/hooks/useExerciseSuggestions")>()),
  useExerciseSuggestions: () => ({ groups: [], isFetching: false }),
}));

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
  useFormatter: () => ({ dateTime: () => "" }),
  useLocale: () => "en",
}));

describe("FinishWizard free-text comments", () => {
  it("collects one multiline comment on the whole workout and previews it as written", () => {
    const onConfirm = vi.fn();
    const note = "Used a lighter sandbag.\nStopped after four rounds.";

    render(
      <FinishWizard
        scores={[]}
        segments={[]}
        comments={[]}
        pendingCommentIds={[]}
        freeText
        isSaving={false}
        feedback={null}
        onConfirm={onConfirm}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));
    fireEvent.change(screen.getByRole("textbox"), { target: { value: note } });
    fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));

    expect(screen.getByText(/Used a lighter sandbag/)).toHaveClass("whitespace-pre-wrap");

    fireEvent.click(screen.getByRole("button", { name: "saveDone3614269" }));
    expect(onConfirm).toHaveBeenCalledWith([], { changes: [], text: note }, [], {});
  });

  it("offers a way back to the workout from the first step", () => {
    const onCancel = vi.fn();

    render(
      <FinishWizard
        scores={[]}
        segments={[]}
        comments={[]}
        pendingCommentIds={[]}
        isSaving={false}
        feedback={null}
        onConfirm={vi.fn()}
        onCancel={onCancel}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "backToWorkoutLabel" }));
    expect(onCancel).toHaveBeenCalledTimes(1);
  });
});

describe("FinishWizard: ADR-180 text-section scores", () => {
  it("asks for each score the coach set, by name, and sends them as numbers", () => {
    const onConfirm = vi.fn();
    render(
      <FinishWizard
        scores={[]}
        segments={[]}
        comments={[]}
        freeText
        textSections={[
          {
            id: "s1",
            title: "Strength",
            body: "Back squat",
            preset: null,
            metrics: [{ key: "top-set", label: "Top set", kind: "load" }],
          },
          { id: "s2", title: "", body: "Run", preset: null, metrics: [] },
          {
            id: "s3",
            title: "",
            body: "AMRAP",
            preset: null,
            metrics: [
              { key: "rounds", label: "Rounds", kind: "rounds" },
              { key: "time", label: "Time", kind: "time" },
            ],
          },
        ]}
        isSaving={false}
        feedback={null}
        onConfirm={onConfirm}
      />,
    );

    fireEvent.change(screen.getByRole("textbox", { name: "Strength · Top set" }), { target: { value: "102,5" } });
    fireEvent.change(screen.getByRole("textbox", { name: "textSectionNumber · Rounds" }), { target: { value: "7" } });
    const time = screen.getByRole("textbox", { name: "textSectionNumber · Time" });
    fireEvent.change(time, { target: { value: "5:3x" } });
    expect(time).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByRole("button", { name: "next2f04eb1" })).toBeDisabled();
    fireEvent.change(time, { target: { value: "5:30" } });

    fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));
    fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));
    expect(screen.getByText("Strength · Top set")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "saveDone3614269" }));
    expect(onConfirm).toHaveBeenCalledWith([], { changes: [], text: null }, [
      { section_id: "s1", metric_key: "top-set", value: 102.5 },
      { section_id: "s3", metric_key: "rounds", value: 7 },
      { section_id: "s3", metric_key: "time", value: 330 },
    ], {});
  });
});

describe("FinishWizard stopped-early question (ADR-549, 3B)", () => {
  it("asks once per section stopped early, optionally, and sends the answer", () => {
    const onConfirm = vi.fn();
    render(
      <FinishWizard
        scores={[]}
        segments={[]}
        comments={[]}
        pendingCommentIds={[]}
        freeText
        stoppedEarly={[{ section_id: "amrap", section_name: "AMRAP 10", ran_ms: 360_000, planned_ms: 600_000 }]}
        isSaving={false}
        feedback={null}
        onConfirm={onConfirm}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));
    fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));

    const question = screen.getByTestId("stopped-early-amrap");
    expect(question).toHaveTextContent("AMRAP 10");
    const shorter = screen.getByRole("button", { name: "stoppedEarlyChoseShorter" });
    expect(shorter).toHaveAttribute("aria-pressed", "false");
    fireEvent.click(shorter);
    expect(shorter).toHaveAttribute("aria-pressed", "true");

    fireEvent.click(screen.getByRole("button", { name: "saveDone3614269" }));
    expect(onConfirm).toHaveBeenCalledWith([], { changes: [], text: null }, [], { amrap: "chose_shorter" });
  });

  it("an unanswered question sends no answer, and a second tap takes the answer back", () => {
    const onConfirm = vi.fn();
    render(
      <FinishWizard
        scores={[]}
        segments={[]}
        comments={[]}
        pendingCommentIds={[]}
        freeText
        stoppedEarly={[{ section_id: "amrap", section_name: "AMRAP 10", ran_ms: 360_000, planned_ms: 600_000 }]}
        isSaving={false}
        feedback={null}
        onConfirm={onConfirm}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));
    fireEvent.click(screen.getByRole("button", { name: "next2f04eb1" }));
    const gaveUp = screen.getByRole("button", { name: "stoppedEarlyGaveUp" });
    fireEvent.click(gaveUp);
    fireEvent.click(gaveUp);

    fireEvent.click(screen.getByRole("button", { name: "saveDone3614269" }));
    expect(onConfirm).toHaveBeenCalledWith([], { changes: [], text: null }, [], {});
  });
});
