import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { chooseValue } from "@/components/ui/select-test-utils";
import type { FreeTextTimerPreset } from "@/lib/free-text-timer";
import type { SectionFormat } from "@/types/workout";

import { TimerChips } from "./TimerChips";

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

const formatLabels = {
  amrap: "AMRAP",
  emom: "EMOM",
  for_time: "For Time",
  tabata: "Tabata",
  custom_hiit: "Custom HIIT",
  death_by: "Death By",
  untimed: "Untimed",
} as Record<SectionFormat, string>;

const frequent: FreeTextTimerPreset[] = [
  { format: "emom", interval_seconds: 60, rounds: 4 },
  { format: "amrap", duration_seconds: 600 },
  { format: "amrap", duration_seconds: 1200 },
];

describe("TimerChips (ADR-571)", () => {
  it("shows the coach's three timers, «No time» and the dropdown", () => {
    render(<TimerChips preset={{ format: "untimed" }} frequent={frequent} formatLabels={formatLabels} onChange={() => {}} />);

    expect(screen.getAllByTestId("timer-chip").map((chip) => chip.textContent)).toEqual(["EMOM 4", "AMRAP 10", "AMRAP 20"]);
    // «No time» is the default: pressed when nothing else was picked.
    expect(screen.getByTestId("timer-chip-no-time")).toHaveTextContent("timerNoTime");
    expect(screen.getByTestId("timer-chip-no-time")).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByTestId("timer-format-select")).toHaveTextContent("timerNoTime");
  });

  it("marks the chip of the section's timer, however it was written", () => {
    render(
      <TimerChips preset={{ format: "emom", rounds: 4, rest_seconds: 15 }} frequent={frequent} formatLabels={formatLabels} onChange={() => {}} />,
    );

    expect(screen.getByRole("button", { name: "EMOM 4" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByTestId("timer-chip-no-time")).toHaveAttribute("aria-pressed", "false");
  });

  it("picks a chip, «No time» or any format from the dropdown", () => {
    const onChange = vi.fn();
    render(<TimerChips preset={{ format: "amrap", duration_seconds: 600 }} frequent={frequent} formatLabels={formatLabels} onChange={onChange} />);

    fireEvent.click(screen.getByRole("button", { name: "AMRAP 20" }));
    expect(onChange).toHaveBeenLastCalledWith({
      format: "amrap",
      duration_seconds: 1200,
    });

    fireEvent.click(screen.getByTestId("timer-chip-no-time"));
    expect(onChange).toHaveBeenLastCalledWith({ format: "untimed" });

    chooseValue(screen.getByTestId("timer-format-select"), "tabata");
    expect(onChange).toHaveBeenLastCalledWith({ format: "tabata" });
  });
});
