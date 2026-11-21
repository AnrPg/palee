"use client";

import { useQuery } from "@tanstack/react-query";

import { fetchAdminWorkout } from "@/api/workouts";
import { WorkoutPreviewDetail } from "@/components/workouts/WorkoutPreviewDetail";
import { useUiTranslations } from "@/i18n/ui";

/**
 * A WOD as staff read it, whole: every section with all its exercises or its
 * text, fetched by id. For screens that only hold the WOD's id and title
 * (the Αρχείο, the WOD of a day), so none of them shows a WOD by its name alone.
 */
export function StaffWorkoutPreview({
  workoutId,
  token,
  version = null,
  initiallyExpanded = true,
}: {
  workoutId: string;
  token: string | null;
  /** The WOD's `updated_at` when known: a newer edit is fetched again. */
  version?: string | null;
  initiallyExpanded?: boolean;
}) {
  const i18n = useUiTranslations();
  const full = useQuery({
    queryKey: ["admin-workout-preview", workoutId, version],
    enabled: Boolean(token),
    queryFn: () => fetchAdminWorkout(token!, workoutId),
    staleTime: 60_000,
  });

  if (!full.data) {
    return (
      <p className="text-sm" role="status" style={{ color: "var(--muted)" }}>
        {full.isError ? i18n("apiErrorRequestFailed") : i18n("workoutPreviewLoading")}
      </p>
    );
  }

  return (
    <WorkoutPreviewDetail
      sections={full.data.sections}
      content={full.data.content}
      initiallyExpanded={initiallyExpanded}
      authoringMode={full.data.authoring_mode}
      freeTextBody={full.data.free_text_body}
      freeTextDocument={full.data.free_text_document}
    />
  );
}
