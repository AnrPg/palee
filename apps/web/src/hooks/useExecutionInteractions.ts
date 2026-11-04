"use client";

import { useCallback, useEffect, useRef } from "react";

import {
  createExecutionAnalytics,
  type ExecutionAnalytics,
  type ExecutionInteractionKind,
  type ExecutionInteractionMetadata,
} from "@/lib/execution-analytics";
import { timerClosedMetadata } from "@/lib/execution-position";
import { useExecutionStore } from "@/stores/execution";

/**
 * ADR-123 / ADR-549: sends the timer's interaction signals (pause, skip,
 * +1 round, finish wizard, …) for one execution, and `timer_closed` when the
 * athlete leaves a workout that is not finished (the tab closes or the
 * screen unmounts), with where they were and how much clock was left, so a
 * workout given up mid-way is known when it happens, not hours later.
 *
 * `track` is stable and never throws; analytics never interrupts a workout.
 * `closeMetadata` says where a runner that keeps its own state (the
 * structured plan runner) stands; the classic timer's store is the default.
 */
export function useExecutionInteractions(
  executionId: string | null,
  accessToken: string | null | undefined,
  closeMetadata?: (now: number) => ExecutionInteractionMetadata | null,
) {
  const tokenRef = useRef(accessToken);
  const closeRef = useRef(closeMetadata);
  useEffect(() => {
    closeRef.current = closeMetadata;
  });
  const analyticsRef = useRef<ExecutionAnalytics | null>(null);

  useEffect(() => {
    tokenRef.current = accessToken;
  }, [accessToken]);

  useEffect(() => {
    if (!executionId) return;
    const analytics = createExecutionAnalytics({ executionId, getToken: () => tokenRef.current });
    analyticsRef.current = analytics;
    let closed = false;

    const close = () => {
      if (closed) return;
      const now = Date.now();
      const metadata = closeRef.current ? closeRef.current(now) : timerClosedMetadata(useExecutionStore.getState(), now);
      if (metadata) {
        closed = true;
        analytics.track("timer_closed", metadata);
      }
      analytics.flushOnExit();
    };
    const onPageHide = () => close();
    // Back from the browser's page cache: the same run goes on.
    const onPageShow = (event: PageTransitionEvent) => {
      if (event.persisted) closed = false;
    };

    window.addEventListener("pagehide", onPageHide);
    window.addEventListener("pageshow", onPageShow);
    return () => {
      window.removeEventListener("pagehide", onPageHide);
      window.removeEventListener("pageshow", onPageShow);
      close();
      void analytics.dispose();
      if (analyticsRef.current === analytics) analyticsRef.current = null;
    };
  }, [executionId]);

  return useCallback((kind: ExecutionInteractionKind, metadata?: ExecutionInteractionMetadata) => {
    analyticsRef.current?.track(kind, metadata);
  }, []);
}
