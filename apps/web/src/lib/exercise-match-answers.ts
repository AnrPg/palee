import type { ExerciseMatch, ExerciseMatchDecision } from "@/api/exercise-matches";

/**
 * ADR-570: the coach's answers to the exercises found in a free-text
 * workout. The same words matched to the same exercise (several rounds of
 * "Thrusters") are one question; a «changed» link (its words no longer name
 * its exercise) is its own question.
 */
export type ExerciseMatchAnswer = "yes" | "no";
export type ExerciseMatchAnswers = Record<string, ExerciseMatchAnswer>;

export type ExerciseMatchGroup = {
  key: string;
  typed: string;
  folded: string;
  exerciseRef: string;
  label: string;
  kind: ExerciseMatch["kind"];
  remembered: boolean;
  muscles: ExerciseMatch["muscles"];
  matches: ExerciseMatch[];
};

export function groupKey(match: Pick<ExerciseMatch, "folded" | "exercise_ref" | "kind">) {
  return `${match.kind === "changed" ? "changed" : "found"}|${match.folded}|${match.exercise_ref}`;
}

export function groupExerciseMatches(matches: ExerciseMatch[]): ExerciseMatchGroup[] {
  const groups = new Map<string, ExerciseMatchGroup>();
  for (const match of matches) {
    const key = groupKey(match);
    const group = groups.get(key);
    if (group) {
      group.matches.push(match);
      group.remembered = group.remembered && match.remembered;
    } else {
      groups.set(key, {
        key,
        typed: match.typed,
        folded: match.folded,
        exerciseRef: match.exercise_ref,
        label: match.label,
        kind: match.kind,
        remembered: match.remembered,
        muscles: Array.isArray(match.muscles) ? match.muscles : [],
        matches: [match],
      });
    }
  }
  return [...groups.values()];
}

/** A match the box confirmed before starts answered «Ναι»; the rest wait for the coach. */
export function initialAnswers(groups: ExerciseMatchGroup[]): ExerciseMatchAnswers {
  return Object.fromEntries(groups.filter((group) => group.remembered).map((group) => [group.key, "yes" as const]));
}

export function allAnswered(groups: ExerciseMatchGroup[], answers: ExerciseMatchAnswers) {
  return groups.every((group) => answers[group.key] === "yes" || answers[group.key] === "no");
}

/** What the box remembers: one decision per question. */
export function matchDecisions(groups: ExerciseMatchGroup[], answers: ExerciseMatchAnswers): ExerciseMatchDecision[] {
  return groups.flatMap((group) => {
    const decision = answers[group.key];
    return decision ? [{ typed: group.typed, exercise_ref: group.exerciseRef, decision }] : [];
  });
}

/**
 * The link each found span gets from its answer: «Ναι» ties it to the
 * exercise (a changed link keeps its exercise, its new words confirmed);
 * «Όχι» is a link without an exercise, kept plain text.
 */
export function linkFor(match: ExerciseMatch, answer: ExerciseMatchAnswer): { ref: string | null; checked: string | null } {
  if (answer === "no") return { ref: null, checked: null };
  return { ref: match.exercise_ref, checked: match.kind === "changed" ? match.folded : null };
}
