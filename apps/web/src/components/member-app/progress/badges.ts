import { semanticLabel, type UiTranslator } from "@/i18n/presentation";

export type BadgeTier = "bronze" | "silver" | "gold" | "platinum" | "master";

/** Tier of a milestone badge from its key (`workouts_50`, `prs_5`, `streak_30`, `amrap_mastery`). */
export function badgeTier(badgeKey: string): BadgeTier {
  if (badgeKey.endsWith("_mastery")) return "master";
  const n = parseInt(badgeKey.split("_")[1] ?? "0", 10);
  if (badgeKey.startsWith("workouts_")) {
    if (n >= 200) return "platinum";
    if (n >= 50) return "gold";
    if (n >= 10) return "silver";
    return "bronze";
  }
  if (badgeKey.startsWith("prs_")) {
    if (n >= 50) return "platinum";
    if (n >= 25) return "gold";
    if (n >= 5) return "silver";
    return "bronze";
  }
  if (badgeKey.startsWith("streak_")) {
    if (n >= 90) return "gold";
    if (n >= 30) return "silver";
    return "bronze";
  }
  return "bronze";
}

export const TIER_ICON: Record<BadgeTier, string> = {
  bronze: "🥉",
  silver: "🥈",
  gold: "🥇",
  platinum: "💎",
  master: "⭐",
};

/** What a badge is for, in the reader's language (Πρόοδος, the profile's «Διακρίσεις»). */
export function badgeDescription(badgeKey: string, i18n: UiTranslator): string {
  if (badgeKey.startsWith("workouts_")) return i18n("completedValue0Workoutsde3ccd4", { value0: badgeKey.split("_")[1] });
  if (badgeKey.startsWith("prs_")) return i18n("loggedValue0PersonalRecords6eb75e4", { value0: badgeKey.split("_")[1] });
  if (badgeKey.startsWith("streak_")) return i18n("maintainedAValue0DayTrainingStreak0dbf33c", { value0: badgeKey.split("_")[1] });
  if (badgeKey.endsWith("_mastery")) return i18n("achievedMasteryInValue01e7e1ec", { value0: semanticLabel(badgeKey.replace("_mastery", ""), i18n) });
  return i18n("trainingMilestoneAchieved56dc32b");
}

/** The short mark inside a badge's disc: its number, or the first letter of a mastery. */
export function badgeMark(badgeKey: string): string {
  const n = badgeKey.split("_")[1];
  if (n && /^\d+$/.test(n)) return n;
  return badgeKey.charAt(0).toUpperCase();
}
