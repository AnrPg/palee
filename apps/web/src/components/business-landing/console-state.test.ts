import { describe, expect, it } from "vitest";

import { CONSOLE_CAPACITY, MAX_TOASTS, PAYMENT_EUROS, consoleReducer, initialConsole, step, toastAt, WARM_UP_TICKS } from "./console-state";

describe("business console state (ADR-556)", () => {
  it("opens warmed up, never empty", () => {
    const state = initialConsole();
    expect(state.tick).toBe(WARM_UP_TICKS);
    expect(state.seats.every((seats) => seats > 0)).toBe(true);
    expect(state.toasts.length).toBeGreaterThan(0);
  });

  it("seats people round robin and starts a full class over", () => {
    let state = initialConsole();
    for (let index = 0; index < 400; index += 1) {
      state = step(state);
      state.seats.forEach((seats, row) => {
        expect(seats).toBeGreaterThanOrEqual(0);
        expect(seats).toBeLessThanOrEqual(CONSOLE_CAPACITY[row]);
      });
    }
    const full = { ...state, tick: 0, seats: [CONSOLE_CAPACITY[0], 0, 0] };
    expect(step(full).seats[0]).toBe(0);
  });

  it("keeps at most three notices, newest last, and counts the takings", () => {
    let state = initialConsole();
    for (let index = 0; index < 30; index += 1) state = step(state);
    expect(state.toasts.length).toBeLessThanOrEqual(MAX_TOASTS);
    expect(state.toasts).toEqual([...state.toasts].sort((a, b) => a - b));
    expect(state.takings % PAYMENT_EUROS).toBe(0);
  });

  it("resets to the warmed-up state", () => {
    const moved = step(step(initialConsole()));
    expect(consoleReducer(moved, { type: "reset" })).toEqual(initialConsole());
  });

  it("cycles through the audience's notices", () => {
    expect(toastAt(["a", "b"], 3)).toBe("b");
    expect(toastAt([], 3)).toBe("");
  });
});
