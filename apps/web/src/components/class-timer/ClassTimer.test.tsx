import { fireEvent, render, screen, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";
import type { PlanSection } from "@/lib/structured-plan/types";

import { ClassTimerControl } from "./ClassTimerControl";
import { ClassTimerDisplay } from "./ClassTimerDisplay";

const send = vi.fn();
let hookValue: Record<string, unknown>;

vi.mock("@/hooks/useClassTimer", () => ({ useClassTimer: () => hookValue }));
vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string, params?: Record<string, unknown>) =>
    params ? `${key}:${JSON.stringify(params)}` : key,
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/lib/organization-slug", () => ({
  adminHref: (href: string, slug: string | null) => (slug ? `/org/${slug}${href}` : href),
  useOrganizationSlug: () => "gym",
}));
vi.mock("@/lib/membership-role", () => ({ useSelectedMembershipRole: () => ({ membershipRole: "coach" }) }));
// «Στην οθόνη» has its own tests (ClassScreenPin.test.tsx).
vi.mock("./ClassScreenPin", () => ({ ClassScreenPin: () => null }));

const segments = [
  { segment_key: "s0", section_id: "a", section_name: "AMRAP 10", format: "amrap", kind: "countdown", phase: "work", duration_seconds: 600, round: null, total_rounds: null, label: "AMRAP 10", exercises: [{ id: "e1", name: "Burpees", prescription_value: 10 }] },
  { segment_key: "s1", section_id: "b", section_name: "Cool down", format: "rest", kind: "countdown", phase: "rest", duration_seconds: 120, round: null, total_rounds: null, label: "Rest", label_key: "rest", exercises: [] },
];

function wrap(ui: ReactNode) {
  return (
    <NextIntlClientProvider locale="en" messages={en} timeZone="UTC">
      {ui}
    </NextIntlClientProvider>
  );
}

function setTimer(status: string, index = 0, startsInMs = 0) {
  hookValue = {
    payload: {
      class: { id: "slot-1", name: "Evening WOD", scheduled_at: "2026-10-12T18:00:00Z", duration_minutes: 60 },
      workout: { id: "w1", title: "Fight Gone Bad" },
      segments,
      timer: { status, current_segment_index: index, segment_started_at_utc: null, paused_elapsed_ms: 0, duration_adjustments: {}, timer_preset: null, lock_version: 3 },
      server_now: "2026-10-12T18:00:00Z",
    },
    position: {
      status,
      index,
      segment: segments[index],
      clock: { elapsedMs: 0, remainingMs: 600_000, limitMs: 600_000, isExpired: false, progress: 0, window: null },
      startsInMs,
    },
    connected: true,
    loadError: null,
    problem: null,
    sending: false,
    send,
  };
}

describe("class timer screens", () => {
  beforeEach(() => send.mockReset());

  it("starts the class from the remote with the chosen get-ready countdown", () => {
    setTimer("ready");
    render(wrap(<ClassTimerControl slotId="slot-1" />));

    fireEvent.click(screen.getByRole("button", { name: 'classTimerCountdownSeconds:{"seconds":5}' }));
    fireEvent.click(screen.getByRole("button", { name: "start952f375" }));

    expect(send).toHaveBeenCalledWith({ command: "start", countdown_seconds: 5 });
    // Controls that cannot work before the start are not shown at all (ANR 2026-11-04).
    expect(screen.queryByRole("button", { name: "nextbc98198" })).toBeNull();
    expect(screen.queryByRole("button", { name: "plusThirtySecondsLabel" })).toBeNull();
    expect(screen.queryByTestId("remote-more")).toBeNull();
  });

  it("shows only the timer chooser when the class has no timed workout", () => {
    setTimer("ready");
    hookValue = { ...hookValue, payload: { ...(hookValue.payload as object), workout: null, segments: [] } };
    render(wrap(<ClassTimerControl slotId="slot-1" />));

    expect(screen.queryByTestId("remote-dock")).toBeNull();
    expect(screen.queryByRole("button", { name: "start952f375" })).toBeNull();
    expect(screen.queryByRole("group", { name: "classTimerGetReadyLabel" })).toBeNull();
    expect(screen.getByText("classTimerNoTimedWorkout")).toBeInTheDocument();

    // A common timer is used with one tap (ANR 2026-11-04).
    fireEvent.click(screen.getByRole("button", { name: "timerPreset_emom10" }));
    expect(send).toHaveBeenLastCalledWith({ command: "configure", timer_preset: { format: "emom", interval_seconds: 60, rounds: 10 } });

    // «?» explains what each common timer's name means.
    expect(screen.queryByTestId("remote-preset-help")).toBeNull();
    fireEvent.click(screen.getByTestId("remote-help-toggle"));
    expect(screen.getByTestId("remote-preset-help")).toHaveTextContent("timerPresetHelp_amrap12");

    // Your own timer comes first and starts from no invented numbers.
    fireEvent.click(screen.getByTestId("remote-own-timer"));
    fireEvent.click(screen.getByTestId("remote-use-timer"));
    expect(send).toHaveBeenLastCalledWith({ command: "configure", timer_preset: { format: "untimed" } });
  });

  it("names Back and Next by what they do on the first and last part", () => {
    setTimer("running", 0);
    const { unmount } = render(wrap(<ClassTimerControl slotId="slot-1" />));
    expect(screen.getByRole("button", { name: "classTimerRestart" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "nextbc98198" })).toBeInTheDocument();
    unmount();

    setTimer("running", 1);
    render(wrap(<ClassTimerControl slotId="slot-1" />));
    expect(screen.getByRole("button", { name: "backc32ae9f" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "classTimerComplete" }));
    expect(send).toHaveBeenLastCalledWith({ command: "next" });
    // On the last part «Τέλος χρονομέτρου» would repeat «Ολοκλήρωση», so the menu keeps only Reset.
    fireEvent.click(screen.getByTestId("remote-more"));
    expect(screen.queryByTestId("remote-finish")).toBeNull();
    expect(screen.getByTestId("remote-reset")).toBeInTheDocument();
  });

  it("asks before resetting a running class and explains every control with «?»", () => {
    setTimer("running");
    render(wrap(<ClassTimerControl slotId="slot-1" />));

    expect(screen.queryAllByTestId("remote-help")).toHaveLength(0);
    fireEvent.click(screen.getByTestId("remote-help-toggle"));
    expect(screen.getByText("classTimerPauseHelp")).toBeInTheDocument();
    expect(screen.getAllByText("classTimerAdjustHelp")).toHaveLength(1);
    expect(screen.getByText("classTimerLiveHelp")).toBeInTheDocument();
    expect(screen.getByTestId("remote-help-header")).toHaveTextContent("classTimerSoundHelp");

    fireEvent.click(screen.getByTestId("remote-more"));
    expect(screen.getByText("classTimerResetHelp")).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("remote-reset"));
    expect(send).not.toHaveBeenCalled();
    fireEvent.click(screen.getByTestId("remote-reset-confirm"));
    expect(send).toHaveBeenCalledWith({ command: "reset" });
  });

  it("hides ±30 s when the current part has no length", () => {
    setTimer("running");
    const untimed = { ...segments[0], kind: "countup", duration_seconds: null };
    hookValue = { ...hookValue, position: { ...(hookValue.position as object), segment: untimed } };
    render(wrap(<ClassTimerControl slotId="slot-1" />));
    expect(screen.queryByRole("button", { name: "plusThirtySecondsLabel" })).toBeNull();
    expect(screen.getByRole("button", { name: "pausecd21a1b" })).toBeInTheDocument();
  });

  it("keeps the wall screen's link, «Στην οθόνη» and open-here in one sheet", () => {
    setTimer("ready");
    render(wrap(<ClassTimerControl slotId="slot-1" />));
    expect(screen.queryByTestId("remote-copy-link")).toBeNull();
    fireEvent.click(screen.getByTestId("remote-wall-screen"));
    expect(screen.getByTestId("remote-copy-link")).toBeInTheDocument();
    expect(screen.getByTestId("remote-open-display")).toHaveAttribute("href", "/org/gym/class-timer/slot-1/display");
  });

  it("pauses, skips, adjusts and jumps while running", () => {
    setTimer("running");
    render(wrap(<ClassTimerControl slotId="slot-1" />));

    fireEvent.click(screen.getByRole("button", { name: "pausecd21a1b" }));
    fireEvent.click(screen.getByRole("button", { name: "plusThirtySecondsLabel" }));
    fireEvent.click(screen.getByText("classTimerJumpTitle"));
    fireEvent.click(screen.getByRole("button", { name: /2\. Cool down/ }));

    expect(send.mock.calls.map(([command]) => command)).toEqual([
      { command: "pause" },
      { command: "adjust", delta_seconds: 30 },
      { command: "jump", index: 1 },
    ]);
  });

  it("shows the clock, the exercises and what is next on the wall", () => {
    setTimer("running");
    render(wrap(<ClassTimerDisplay slotId="slot-1" />));

    expect(screen.getByRole("timer")).toHaveTextContent("10:00");
    expect(screen.getByText("Fight Gone Bad")).toBeInTheDocument();
    expect(screen.getByText(/nextUpLabel/)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "classTimerRemoteLink" })).toHaveAttribute("href", "/org/gym/class-timer/slot-1/control");
  });

  it("shows the get-ready countdown before the start", () => {
    setTimer("running", 0, 4_200);
    render(wrap(<ClassTimerDisplay slotId="slot-1" />));

    expect(screen.getByRole("timer")).toHaveTextContent("5");
    expect(screen.getByText("getReadyLabel")).toBeInTheDocument();
  });

  it("shows what the room does now on the wall and on the remote", () => {
    setTimer("running");
    const wall = render(wrap(<ClassTimerDisplay slotId="slot-1" />));
    const panel = screen.getByTestId("timer-now");
    expect(panel).toHaveAttribute("data-scope", "section");
    expect(within(panel).getByText("This section")).toBeInTheDocument();
    expect(within(panel).getByText("Burpees")).toBeInTheDocument();
    wall.unmount();

    render(wrap(<ClassTimerControl slotId="slot-1" />));
    expect(within(screen.getByTestId("timer-now")).getByText("Burpees")).toBeInTheDocument();
  });

  it("shows this interval's exercises of a structured plan WOD, and the next one while resting", () => {
    const plan: PlanSection = {
      v: 1,
      flow: "intervals",
      params: { work: "40″", off: "20″", rounds: "4" },
      blocks: [
        [{ id: "r1", kind: "ex", name: "Wall ball", dose: "15", load: "9kg", cells: [] }],
        [{ id: "r2", kind: "ex", name: "Row", dose: "12 cal", load: "", cells: [] }],
      ],
      score: "",
    };
    const segment = {
      segment_key: "plan:p1", section_id: "p1", section_name: "Engine", format: "structured_plan", kind: "interval_cycle", phase: "work",
      duration_seconds: 40, round: null, total_rounds: 7, label: "Engine", exercises: [],
      timer_config: { plan_flow: "intervals", interval_pattern_seconds: [40, 20] },
    };
    const show = (window: number) => {
      hookValue = {
        ...hookValue,
        payload: { ...(hookValue.payload as object), workout: { id: "w1", title: "Engine", body: { kind: "plan", sections: [{ id: "p1", name: "Engine", plan }] } }, segments: [segment] },
        position: {
          status: "running", index: 0, segment, startsInMs: 0,
          clock: { elapsedMs: 0, remainingMs: 30_000, limitMs: 220_000, isExpired: false, progress: 0, window: { index: window, count: 7, elapsedMs: 0, lengthMs: 40_000 } },
        },
      };
    };

    setTimer("running");
    show(3);
    const { rerender } = render(wrap(<ClassTimerDisplay slotId="slot-1" />));
    // Window 3 = round 2, the second kind of round.
    expect(within(screen.getByTestId("timer-now")).getByText("Row")).toBeInTheDocument();
    expect(screen.getByText(/timerRoundLabel:\{"round":2,"rounds":4\}/)).toBeInTheDocument();

    show(4);
    rerender(wrap(<ClassTimerDisplay slotId="slot-1" />));
    expect(screen.getByTestId("timer-now")).toHaveAttribute("data-upcoming", "true");
    expect(within(screen.getByTestId("timer-now")).getByText("Wall ball")).toBeInTheDocument();
    expect(screen.getByText("restPhaseLabel")).toBeInTheDocument();
  });
});
