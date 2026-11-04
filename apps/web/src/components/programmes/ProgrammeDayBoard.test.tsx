import { fireEvent, render, screen, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

import { readDays } from "./programme-day-model";
import { ProgrammeDayBoard } from "./ProgrammeDayBoard";

const workout = (id: string, title: string, done = false) => ({ workout_id: id, assigned_workout_id: `a-${id}`, done, title, summary: null });

const payload = {
  starts_on: "2026-10-26",
  today: "2026-11-05",
  weeks: 6,
  progress: { done: 6, total: 24, skipped: 0, behind: 1, remaining: 18 },
  behind: { day: 8, week: 2, weekday: 1, date: "2026-11-03", can_do_today: true, can_skip: true },
  days: [
    { day: 0, status: "done", date: "2026-10-26", workouts: [workout("w0", "Back squat 5×5", true)] },
    { day: 7, status: "done", date: "2026-11-02", workouts: [workout("w7", "Front squat 5×3", true)] },
    { day: 8, status: "behind", date: "2026-11-03", workouts: [workout("w8", "Helen")] },
    { day: 10, status: "today", date: "2026-11-05", workouts: [workout("w10", "Deadlift 5×5")] },
    { day: 12, status: "upcoming", date: "2026-11-07", workouts: [workout("w12", "Engine 30′")] },
  ],
};

function wrap(data: unknown, onAction = vi.fn(), error: string | null = null) {
  render(
    <NextIntlClientProvider locale="el" messages={el}>
      <ProgrammeDayBoard view={readDays(data)} pending={false} error={error} onAction={onAction} />
    </NextIntlClientProvider>,
  );
  return onAction;
}

// Board 3κ/3μ A (ADR-540): progress, «Έμεινε πίσω», day strip, today with «Ξεκίνα», the week.
describe("ProgrammeDayBoard", () => {
  it("shows the progress, today with «Ξεκίνα» and the week", () => {
    wrap(payload);
    expect(screen.getByText("Εβδομάδα 2 από 6")).toBeTruthy();
    expect(screen.getByTestId("programme-progress").textContent).toBe("6 / 24 προπονήσεις");
    const card = screen.getByTestId("programme-day-card");
    expect(within(card).getByText("Deadlift 5×5")).toBeTruthy();
    expect(within(card).getByText(/^Σήμερα · Εβδ\. 2 · Ημ\. 4/)).toBeTruthy();
    expect(within(card).getByRole("link", { name: "Ξεκίνα" }).getAttribute("href")).toBe("/box/workouts?open_assignment=a-w10");
    expect(screen.getByRole("heading", { name: "Αυτή την εβδομάδα" })).toBeTruthy();
  });

  it("offers «Κάν' τη σήμερα» and «Παράλειψη» on the day left behind", () => {
    const onAction = wrap(payload);
    const behind = screen.getByTestId("programme-behind");
    expect(within(behind).getByText("Έμεινε πίσω η Ημ. 2 (Τρίτη)")).toBeTruthy();
    fireEvent.click(within(behind).getByRole("button", { name: "Κάν' τη σήμερα" }));
    expect(onAction).toHaveBeenCalledWith("today", 8);
    fireEvent.click(within(behind).getByRole("button", { name: "Παράλειψη" }));
    expect(onAction).toHaveBeenCalledWith("skip", 8);
  });

  it("offers only «Παράλειψη» when the day cannot move any more, and shows a refusal", () => {
    wrap({ ...payload, behind: { ...payload.behind, can_do_today: false } }, vi.fn(), "Δεν γίνεται άλλη μετακίνηση.");
    const behind = screen.getByTestId("programme-behind");
    expect(within(behind).queryByRole("button", { name: "Κάν' τη σήμερα" })).toBeNull();
    expect(within(behind).getByText("Δεν χωράει άλλη μετακίνηση. Μπορείς να την παραλείψεις.")).toBeTruthy();
    expect(within(behind).getByText("Δεν γίνεται άλλη μετακίνηση.")).toBeTruthy();
  });

  it("shows the day picked in the strip, and moves between weeks", () => {
    wrap(payload);
    fireEvent.click(within(screen.getByTestId("programme-day-strip")).getByRole("button", { name: "Ημ. 6 · Επόμενη" }));
    const card = screen.getByTestId("programme-day-card");
    expect(within(card).getByText("Engine 30′")).toBeTruthy();
    expect(within(card).queryByRole("link", { name: "Ξεκίνα" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Προηγούμενη εβδομάδα" }));
    expect(screen.getByRole("heading", { name: "Εβδομάδα 1" })).toBeTruthy();
    expect(within(screen.getByTestId("programme-day-card")).getByRole("link", { name: "Δες την καταγραφή" })).toBeTruthy();
  });

  it("survives a stub that answers {}", () => {
    wrap({});
    expect(screen.getByTestId("programme-days-empty").textContent).toBe("Δεν υπάρχουν ακόμη μέρες σε αυτό το πρόγραμμα προπόνησης.");
  });
});
