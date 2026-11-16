"use client";

import { useQuery } from "@tanstack/react-query";
import { useMemo } from "react";

import { fetchFrequentTimers, FREQUENT_TIMERS_KEY } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { parseFreeTextTimerPreset, type FreeTextTimerPreset } from "@/lib/free-text-timer";
import { FRESHNESS } from "@/lib/query-policy";

const NONE: FreeTextTimerPreset[] = [];

/**
 * ADR-571: the coach's most used timers, most used first, never «Χωρίς
 * χρόνο». The text-section chips show them, and since ADR-650 both text
 * editors offer them first among the formats while typing.
 */
export function useFrequentTimers(): FreeTextTimerPreset[] {
  const { tokens } = useSession();
  const accessToken = tokens?.access_token;
  const query = useQuery({
    queryKey: FREQUENT_TIMERS_KEY,
    enabled: Boolean(accessToken),
    queryFn: () => fetchFrequentTimers(accessToken!),
    staleTime: FRESHNESS.reference,
  });
  return useMemo(
    () =>
      query.data?.presets
        ? query.data.presets.flatMap((chip) => {
            const preset = parseFreeTextTimerPreset(chip.preset);
            return preset && preset.format !== "untimed" ? [preset] : [];
          })
        : NONE,
    [query.data],
  );
}
