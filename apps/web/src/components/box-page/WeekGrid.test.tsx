import { fireEvent, render, screen, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

import { WeekGrid } from "./VisitorSchedule";

type GridSlot = Parameters<typeof WeekGrid>[0]["slots"][number];

const slot = (id: string, at: string, extra: Partial<GridSlot> = {}) =>
  ({ id, name: "Hybrid", scheduled_at: at, duration_minutes: 60, spots_remaining: 4, coach: { nickname: "Χριστόφορος" }, ...extra }) as GridSlot;

function grid(slots: GridSlot[], onOpen = vi.fn()) {
  render(
    <NextIntlClientProvider locale="el" messages={el} timeZone="Europe/Athens">
      <WeekGrid monday="2099-11-09" today="2099-11-10" zone="Europe/Athens" slots={slots} locale="el" trial={() => false} onOpen={onOpen} />
    </NextIntlClientProvider>,
  );
  return onOpen;
}

// ADR-621 (S1): desktop shows the whole week in seven columns.
describe("WeekGrid", () => {
  it("puts each class under its day, in seven columns, today marked", () => {
    grid([slot("a", "2099-11-10T15:30:00Z"), slot("b", "2099-11-12T16:30:00Z", { name: "Mobility" })]);
    const days = screen.getAllByRole("listitem");
    expect(days).toHaveLength(7);
    expect(days[1]!.getAttribute("aria-current")).toBe("date");
    expect(within(days[1]!).getByRole("button").textContent).toContain("17:30");
    expect(within(days[3]!).getByRole("button").textContent).toContain("Mobility");
    expect(within(days[0]!).queryByRole("button")).toBeNull();
  });

  it("says when a class is full and opens a class on click", () => {
    const onOpen = grid([slot("a", "2099-11-11T15:30:00Z", { spots_remaining: 0 })]);
    const tile = screen.getByRole("button");
    expect(tile.textContent).toContain("Πλήρες");
    fireEvent.click(tile);
    expect(onOpen).toHaveBeenCalledWith(expect.objectContaining({ id: "a" }));
  });
});
