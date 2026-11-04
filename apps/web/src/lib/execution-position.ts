import type { TimerSegment } from "@/api/executions";
import type { ExecutionInteractionMetadata } from "@/lib/execution-analytics";

/** What `ExecutionInteraction` accepts as a token (ids, formats). */
const TOKEN = /^[A-Za-z0-9_-]{1,64}$/;
const MAX_MS = 86_400_000;

type PositionState = {
  status: string;
  currentSegmentIndex: number;
  segments: TimerSegment[];
  currentElapsedMs: (now?: number) => number;
};

const clampMs = (ms: number) => Math.min(MAX_MS, Math.max(0, Math.round(ms)));

/**
 * Where the athlete is in the sequence, as interaction metadata: segment
 * index, and the section id and format when the server accepts them as
 * tokens (a between-sections segment's synthetic id is left out, so one
 * odd id can never reject a whole batch).
 */
export function positionMetadata(state: PositionState): ExecutionInteractionMetadata {
  const segment = state.segments[state.currentSegmentIndex];
  const metadata: ExecutionInteractionMetadata = { segment_index: Math.max(0, state.currentSegmentIndex) };
  if (segment?.section_id && TOKEN.test(segment.section_id)) metadata.section_id = segment.section_id;
  if (segment?.format && TOKEN.test(String(segment.format))) metadata.format = String(segment.format);
  return metadata;
}

/**
 * ADR-549: `timer_closed` metadata, or null when there is nothing running to
 * leave (not started yet, or already completed): the position, the time run
 * in the current segment and, on a clock with a set length, what was left.
 */
export function timerClosedMetadata(state: PositionState, now: number): ExecutionInteractionMetadata | null {
  if (state.status !== "active" && state.status !== "paused") return null;
  const segment = state.segments[state.currentSegmentIndex];
  const elapsed = clampMs(state.currentElapsedMs(now));
  const metadata: ExecutionInteractionMetadata = { ...positionMetadata(state), elapsed_ms: elapsed };
  const seconds = segment?.duration_seconds;
  if (segment?.kind === "countdown" && typeof seconds === "number" && seconds > 0) {
    metadata.remaining_ms = clampMs(seconds * 1000 - elapsed);
  }
  return metadata;
}
