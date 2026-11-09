/**
 * The business hero's console (ADR-556) as a pure state machine, so the
 * rules are tested without timers. Each tick seats one person in the next
 * class (round robin); a full class starts over on the following round,
 * which keeps the picture moving forever. Every few ticks a check-in,
 * a payment and a notice come in.
 */

/** Places in the three classes on the console. */
export const CONSOLE_CAPACITY = [16, 12, 20] as const;
/** How many notices show at once. */
export const MAX_TOASTS = 2;
/** One package payment adds this much to the day's takings. */
export const PAYMENT_EUROS = 49;

export type ConsoleState = {
  tick: number;
  seats: number[];
  bookings: number;
  checkIns: number;
  takings: number;
  /** Ids of the notices on screen: the n-th notice of the day, oldest first. */
  toasts: number[];
};

export type ConsoleAction = { type: "tick" } | { type: "reset" };

/** Ticks played before the first paint, so the console never opens empty. */
export const WARM_UP_TICKS = 14;

export function step(state: ConsoleState): ConsoleState {
  const row = state.tick % CONSOLE_CAPACITY.length;
  const seats = [...state.seats];
  seats[row] = seats[row] >= CONSOLE_CAPACITY[row] ? 0 : seats[row] + 1;
  const toasts = state.tick % 3 === 0 ? [...state.toasts, state.tick / 3].slice(-MAX_TOASTS) : state.toasts;
  return {
    tick: state.tick + 1,
    seats,
    bookings: state.bookings + 1,
    checkIns: state.checkIns + (state.tick % 2 === 0 ? 1 : 0),
    takings: state.takings + (state.tick % 4 === 1 ? PAYMENT_EUROS : 0),
    toasts,
  };
}

export function initialConsole(): ConsoleState {
  let state: ConsoleState = { tick: 0, seats: CONSOLE_CAPACITY.map(() => 0), bookings: 0, checkIns: 0, takings: 0, toasts: [] };
  for (let index = 0; index < WARM_UP_TICKS; index += 1) state = step(state);
  return state;
}

export function consoleReducer(state: ConsoleState, action: ConsoleAction): ConsoleState {
  return action.type === "reset" ? initialConsole() : step(state);
}

/** The words of notice `id`: the audience's notices take turns. */
export function toastAt(messages: string[], id: number) {
  return messages.length === 0 ? "" : messages[id % messages.length];
}
