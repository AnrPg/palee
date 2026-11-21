import { workoutFamiliesLook, workoutTypeColor } from "@/lib/theme";
import { workoutKindFamilies, type WorkoutKindCatalogue } from "@/lib/workout-kinds";

export const WORKOUT_TYPE_COLORS: Record<string, string> = {
  crossfit: "var(--workout-crossfit)",
  strength: "var(--workout-strength)",
  gymnastics: "var(--workout-gymnastics)",
  aerobics: "var(--workout-aerobics)",
  flexibility: "var(--workout-flexibility)",
  recovery: "var(--workout-recovery)",
};

export { workoutTypeColor };

type KindedWorkout = { type?: string | null; types?: readonly string[] | null; families?: readonly string[] | null };

/** ADR-690: a WOD's colour (text, tints) and stripe (bars) from its families. */
export function workoutLook(workout: KindedWorkout | null | undefined, catalogue?: WorkoutKindCatalogue) {
  return workoutFamiliesLook(workoutKindFamilies(workout, catalogue));
}

/** ADR-690: a WOD's colour for text and tints: its (first) family's. */
export function workoutColor(workout: KindedWorkout | null | undefined, catalogue?: WorkoutKindCatalogue) {
  return workoutLook(workout, catalogue).color;
}
