"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { ApiError } from "@/api/client";
import {
  type ClassTimerCommand,
  type ClassTimerPayload,
  fetchClassTimer,
  sendClassTimerCommand,
} from "@/api/class-timers";
import { classTimerPosition, clockOffsetMs, followsPayload } from "@/lib/class-timer";
import { subscribeToTopic } from "@/lib/realtime";

const TICK_MS = 250;

export type ClassTimerProblem = "conflict" | "rejected" | "offline" | "forbidden" | null;

/**
 * Follows a class timer live: loads it, applies every update pushed on
 * `class_timer:<slot>`, refetches after reconnecting or returning to the tab,
 * and corrects for this device's clock being off from the server's.
 * `send` runs coach commands one at a time against the latest version; a
 * conflict refetches instead of re-sending, so "Next" is never applied twice.
 *
 * ADR-746: a class may hold several WODs, each with its own timer, all pushed
 * on the same topic. Without `workoutId` the hook follows the coach's «Τώρα»
 * (wall display, box screens, members who follow the coach) and switches with
 * it; with one, it follows that WOD's timer only.
 */
export function useClassTimer(
  accessToken: string | null | undefined,
  slotId: string | null,
  options: { workoutId?: string | null } = {},
) {
  const workoutId = options.workoutId ?? null;
  const [payload, setPayload] = useState<ClassTimerPayload | null>(null);
  const [loadError, setLoadError] = useState<unknown>(null);
  const [connected, setConnected] = useState(false);
  const [problem, setProblem] = useState<ClassTimerProblem>(null);
  const [sending, setSending] = useState(false);
  const [offsetMs, setOffsetMs] = useState(0);
  const [now, setNow] = useState(() => Date.now());
  const latest = useRef<ClassTimerPayload | null>(null);
  const queue = useRef<Promise<unknown>>(Promise.resolve());

  const adopt = useCallback(
    (next: ClassTimerPayload, pushed = false) => {
      if (pushed && !followsPayload(next, workoutId)) return;
      // Ignore pushes older than what we already have for the same WOD
      // (another WOD's timer keeps its own version).
      const current = latest.current;
      if (
        current &&
        (current.workout?.id ?? null) === (next.workout?.id ?? null) &&
        next.timer.lock_version < current.timer.lock_version
      )
        return;
      latest.current = next;
      setPayload(next);
    },
    [workoutId],
  );

  const refresh = useCallback(async () => {
    if (!accessToken || !slotId) return;
    const sentAt = Date.now();
    try {
      const next = await fetchClassTimer(accessToken, slotId, workoutId);
      setOffsetMs(clockOffsetMs(next.server_now, sentAt, Date.now()));
      latest.current = null;
      adopt(next);
      setLoadError(null);
    } catch (error) {
      setLoadError(error);
    }
  }, [accessToken, adopt, slotId, workoutId]);

  // Initial load (refresh() handles later reloads).
  useEffect(() => {
    if (!accessToken || !slotId) return;
    let cancelled = false;
    const sentAt = Date.now();
    fetchClassTimer(accessToken, slotId, workoutId)
      .then((next) => {
        if (cancelled) return;
        setOffsetMs(clockOffsetMs(next.server_now, sentAt, Date.now()));
        latest.current = null;
        adopt(next);
      })
      .catch((error: unknown) => {
        if (!cancelled) setLoadError(error);
      });
    return () => {
      cancelled = true;
    };
  }, [accessToken, adopt, slotId, workoutId]);

  useEffect(() => {
    if (!accessToken || !slotId) return;
    return subscribeToTopic(
      accessToken,
      `class_timer:${slotId}`,
      { "class_timer:updated": (next) => adopt(next as ClassTimerPayload, true) },
      {
        onJoin: () => {
          setConnected(true);
          void refresh();
        },
        onDisconnect: () => setConnected(false),
        onChannelError: () => setConnected(false),
        onJoinError: () => setConnected(false),
      },
    );
  }, [accessToken, adopt, refresh, slotId]);

  useEffect(() => {
    const tick = () => setNow(Date.now());
    const interval = window.setInterval(tick, TICK_MS);
    const onVisible = () => {
      if (document.visibilityState === "visible") {
        tick();
        void refresh();
      }
    };
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("online", onVisible);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("online", onVisible);
    };
  }, [refresh]);

  const send = useCallback(
    (command: ClassTimerCommand) => {
      if (!accessToken || !slotId) return Promise.resolve(false);
      const run = async () => {
        const current = latest.current;
        if (!current) return false;
        setSending(true);
        setProblem(null);
        const sentAt = Date.now();
        try {
          const next = await sendClassTimerCommand(
            accessToken,
            slotId,
            command,
            current.timer.lock_version,
            current.workout?.id ?? workoutId,
          );
          setOffsetMs(clockOffsetMs(next.server_now, sentAt, Date.now()));
          adopt(next);
          return true;
        } catch (error) {
          if (error instanceof ApiError && error.status === 409) {
            setProblem("conflict");
            await refresh();
          } else if (error instanceof ApiError && error.status === 403) {
            setProblem("forbidden");
          } else if (error instanceof ApiError && error.status === 422) {
            setProblem("rejected");
          } else {
            setProblem("offline");
          }
          return false;
        } finally {
          setSending(false);
        }
      };
      const result = queue.current.then(run, run);
      queue.current = result;
      return result;
    },
    [accessToken, adopt, refresh, slotId, workoutId],
  );

  const serverNow = now + offsetMs;
  // A partial answer (no timer yet) shows no position rather than crashing the page.
  const position = payload?.timer ? classTimerPosition(payload.segments ?? [], payload.timer, serverNow) : null;

  return { payload, position, serverNow, connected, loadError, problem, sending, send, refresh };
}

