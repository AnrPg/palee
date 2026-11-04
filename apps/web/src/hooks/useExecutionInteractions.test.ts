import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { TimerSegment } from "@/api/executions";
import { useExecutionStore } from "@/stores/execution";

import { useExecutionInteractions } from "./useExecutionInteractions";

const apiRequest = vi.fn();

vi.mock("@/api/client", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/client")>()),
  apiRequest: (...args: unknown[]) => apiRequest(...args),
}));

const amrap = {
  segment_key: "segment:0",
  section_id: "sec1",
  section_name: "AMRAP",
  format: "amrap",
  kind: "countdown",
  duration_seconds: 600,
  exercises: [],
} as unknown as TimerSegment;

type Sent = { body: { events: { kind: string; metadata?: Record<string, number | string> }[] }; keepalive?: boolean };
const sent = () => apiRequest.mock.calls.map((call) => call[1] as Sent);

describe("useExecutionInteractions (ADR-549)", () => {
  beforeEach(() => {
    apiRequest.mockReset().mockResolvedValue({ accepted: 1, duplicates: 0 });
    useExecutionStore.getState().reset();
    useExecutionStore.getState().initExecution({
      executionId: "execution-1",
      workoutId: "workout-1",
      scaleSlug: null,
      segments: [amrap],
      status: "paused",
      pausedElapsed: 240_000,
    });
  });

  it("sends timer_closed with the clock left when the screen is left mid-workout", () => {
    const { result, unmount } = renderHook(() => useExecutionInteractions("execution-1", "token"));
    act(() => result.current("pause", { segment_index: 0 }));
    unmount();

    const [request] = sent();
    expect(request.keepalive).toBe(true);
    expect(request.body.events.map((event) => event.kind)).toEqual(["pause", "timer_closed"]);
    expect(request.body.events[1].metadata).toMatchObject({ section_id: "sec1", elapsed_ms: 240_000, remaining_ms: 360_000 });
  });

  it("sends timer_closed once when the page hides, and nothing for a finished workout", () => {
    const { unmount } = renderHook(() => useExecutionInteractions("execution-1", "token"));
    act(() => {
      window.dispatchEvent(new Event("pagehide"));
    });
    expect(sent().flatMap((request) => request.body.events.map((event) => event.kind))).toEqual(["timer_closed"]);

    useExecutionStore.getState().completeExecution();
    unmount();
    expect(sent()).toHaveLength(1);
  });
});
