import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import el from "../../../../messages/el.json";
import { findTextTimers } from "@/lib/wod-formats/parse";
import type { SectionFormat } from "@/types/workout";

import { ExerciseMatchesDialog } from "./ExerciseMatchesDialog";
import { TextTimerNote } from "./TextTimerNote";

const labels = new Proxy({}, { get: (_target, key) => String(key).toUpperCase().replace("_", " ") }) as Record<SectionFormat, string>;
const withIntl = (node: React.ReactNode) => (
  <NextIntlClientProvider locale="el" messages={el}>
    {node}
  </NextIntlClientProvider>
);

describe("TextTimerNote (ADR-650)", () => {
  it("shows the timer the text set, «Αλλαγή», and «βρέθηκαν 2» with the sections note", () => {
    const onChange = vi.fn();
    const onNext = vi.fn();
    const found = findTextTimers("EMOM 10\n\nAMRAP 12");
    render(
      withIntl(
        <TextTimerNote preset={found.timers[0]!.preset} source={{ from: "text", pick: 0 }} found={found} formatLabels={labels} oneTimer onChange={onChange} onRestore={vi.fn()} onNext={onNext} />,
      ),
    );
    expect(screen.getByTestId("text-timer-chip")).toHaveTextContent(/EMOM 10\s*· από το κείμενο/);
    expect(screen.getByText("βρέθηκαν 2")).toBeInTheDocument();
    expect(screen.getByText(/Χώρισέ το σε ενότητες/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Αλλαγή" }));
    fireEvent.click(screen.getByRole("button", { name: "Το επόμενο" }));
    expect(onChange).toHaveBeenCalled();
    expect(onNext).toHaveBeenCalled();
  });

  it("offers «Από το κείμενο» after a change by hand", () => {
    const onRestore = vi.fn();
    render(
      withIntl(
        <TextTimerNote preset={{ format: "for_time" }} source={{ from: "hand", pick: 0 }} found={findTextTimers("AMRAP 12")} formatLabels={labels} oneTimer onRestore={onRestore} onNext={vi.fn()} />,
      ),
    );
    expect(screen.queryByTestId("text-timer-chip")).toBeNull();
    fireEvent.click(screen.getByTestId("text-timer-restore"));
    expect(onRestore).toHaveBeenCalled();
  });

  it("says what is missing from «AMRAP» alone, and nothing for a text without a format", () => {
    const { rerender } = render(
      withIntl(<TextTimerNote preset={null} source={{ from: "text", pick: 0 }} found={findTextTimers("AMRAP\n10 burpees")} formatLabels={labels} oneTimer onRestore={vi.fn()} onNext={vi.fn()} />),
    );
    expect(screen.getByText(/«AMRAP 12»/)).toBeInTheDocument();
    rerender(withIntl(<TextTimerNote preset={null} source={{ from: "text", pick: 0 }} found={findTextTimers("10 burpees")} formatLabels={labels} oneTimer onRestore={vi.fn()} onNext={vi.fn()} />));
    expect(screen.queryByTestId("text-timer-note")).toBeNull();
  });
});

describe("the publish dialog with a timer from the text (ADR-650, Ε1)", () => {
  it("asks only about the timer when no exercise was found, and publishes after «Ναι»", () => {
    const onConfirm = vi.fn();
    const onChangeTimer = vi.fn();
    render(withIntl(<ExerciseMatchesDialog matches={[]} timer="AMRAP 12" onChangeTimer={onChangeTimer} busy={false} error={null} onBack={vi.fn()} onConfirm={onConfirm} />));
    expect(screen.getByText("Έλεγξε το χρονόμετρο")).toBeInTheDocument();
    expect(screen.getByTestId("text-timer-row")).toHaveTextContent("Χρονόμετρο από το κείμενο: AMRAP 12");
    const publish = screen.getByRole("button", { name: "Δημοσίευση" });
    expect(publish).toBeDisabled();
    fireEvent.click(screen.getByRole("button", { name: "Ναι" }));
    expect(publish).toBeEnabled();
    fireEvent.click(publish);
    expect(onConfirm).toHaveBeenCalledWith({});
    fireEvent.click(screen.getByRole("button", { name: "Αλλαγή" }));
    expect(onChangeTimer).toHaveBeenCalled();
  });
});

describe("TextTimerNote help (ADR-650)", () => {
  it("shows the help button whenever the note shows, and nothing when the text has no timer", () => {
    const found = findTextTimers("AMRAP 12");
    const help = <button type="button">help</button>;
    const { rerender } = render(
      withIntl(<TextTimerNote preset={found.timers[0]!.preset} source={{ from: "text", pick: 0 }} found={found} formatLabels={labels} oneTimer help={help} onRestore={vi.fn()} onNext={vi.fn()} />),
    );
    expect(screen.getByRole("button", { name: "help" })).toBeInTheDocument();
    rerender(withIntl(<TextTimerNote preset={null} source={{ from: "text", pick: 0 }} found={findTextTimers("Back squat")} formatLabels={labels} oneTimer help={help} onRestore={vi.fn()} onNext={vi.fn()} />));
    expect(screen.queryByRole("button", { name: "help" })).toBeNull();
  });
});
