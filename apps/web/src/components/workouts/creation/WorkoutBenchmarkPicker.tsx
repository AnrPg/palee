"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { WORKOUT_BENCHMARKS_KEY, fetchWorkoutBenchmarks, setWorkoutBenchmark, type WorkoutBenchmark } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { AdvancedDisclosure } from "@/components/settings/AdvancedSettings";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";

const GROUPS: WorkoutBenchmark["group"][] = ["metcon", "monostructural", "gymnastics", "strength", "power"];

/**
 * ADR-394: under «Προχωρημένα» of the WOD editor, the coach says this WOD is
 * a known benchmark (Fran, Grace, Murph, a max back squat…) so its scores
 * also rank on «Όλο το Palee». Never guessed from the title; saved at once.
 */
export function WorkoutBenchmarkPicker({ workoutId, initialKey }: { workoutId: string; initialKey: string | null }) {
  const t = useTranslations("TrainingFloor");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [value, setValue] = useState<string | null>(initialKey);
  const catalog = useQuery({
    queryKey: WORKOUT_BENCHMARKS_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchWorkoutBenchmarks(token!),
    staleTime: Infinity,
  });
  const save = useMutation({
    mutationFn: (key: string | null) => setWorkoutBenchmark(token!, workoutId, key),
    onSuccess: (result) => setValue(result.benchmark?.key ?? null),
  });

  const benchmarks = catalog.data?.benchmarks ?? [];

  return (
    <AdvancedDisclosure count={1} testId="workout-benchmark-advanced">
      <div className="space-y-2">
        <label htmlFor="workout-benchmark" className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("benchmarkPickerTitle")}
        </label>
        <p className="text-xs" style={{ color: "var(--muted)" }}>{t("benchmarkPickerHint")}</p>
        <Select
          id="workout-benchmark"
          value={value ?? ""}
          disabled={!catalog.data || save.isPending}
          onValueChange={(next) => save.mutate(next || null)}
          className="w-full rounded-xl px-3 py-2 text-sm"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          <option value="">{t("benchmarkNone")}</option>
          {GROUPS.map((group) => (
            <optgroup key={group} label={t(`domain_${group}`)}>
              {benchmarks
                .filter((benchmark) => benchmark.group === group)
                .map((benchmark) => (
                  <option key={benchmark.key} value={benchmark.key}>
                    {t(`benchmark_${benchmark.key}`)}
                  </option>
                ))}
            </optgroup>
          ))}
        </Select>
        {save.isError ? <ErrorNotice variant="field">{t("benchmarkSaveFailed")}</ErrorNotice> : null}
      </div>
    </AdvancedDisclosure>
  );
}
