/**
 * What the guest landing's stories do on a tap, a hold or the end of a slide
 * (ADR-555). Pure, so the rules are tested without timers or pointers.
 */

/** A press held this long pauses the story instead of turning the page. */
export const HOLD_TO_PAUSE_MS = 250;
/* How long one story plays is the bar's animation (5s, .landing-story-fill in globals.css). */

export type StoryState = { index: number; paused: boolean; holding: boolean };

export type StoryAction =
  | { type: "next" }
  | { type: "previous" }
  | { type: "go"; index: number }
  | { type: "toggle" }
  | { type: "hold" }
  | { type: "release" };

export function storyReducer(total: number) {
  return (state: StoryState, action: StoryAction): StoryState => {
    switch (action.type) {
      // After the last story the player starts again from the first.
      case "next":
        return { ...state, index: (state.index + 1) % total };
      case "previous":
        return { ...state, index: Math.max(state.index - 1, 0) };
      case "go":
        return { ...state, index: Math.min(Math.max(action.index, 0), total - 1) };
      case "toggle":
        return { ...state, paused: !state.paused };
      case "hold":
        return { ...state, holding: true };
      case "release":
        return { ...state, holding: false };
    }
  };
}

/** Whether the bar of the current story is running. */
export function isPlaying(state: StoryState) {
  return !state.paused && !state.holding;
}

/**
 * Which way a tap turns the page: the first third of the screen goes back,
 * the rest goes on. In a right-to-left language the sides swap.
 */
export function tapDirection(x: number, width: number, rtl: boolean): "previous" | "next" {
  const fromStart = rtl ? width - x : x;
  return fromStart < width / 3 ? "previous" : "next";
}
