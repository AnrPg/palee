/**
 * The workout kinds (ADR-275), mirroring `Palee.Workouts.Domain.WorkoutType`:
 * one fixed list, grouped in families. Stats, badges, colours and icons read
 * the family, so a new kind only joins a family here and in the API.
 * `aerobics` and `flexibility` are the original kinds and stay valid.
 */
export const WORKOUT_TYPE_FAMILIES = [
  { family: "functional", types: ["crossfit", "functional_fitness", "hyrox", "hiit", "bootcamp", "circuit_training"] },
  { family: "strength", types: ["strength", "powerlifting", "olympic_lifting", "bodybuilding", "strongman", "kettlebell"] },
  {
    family: "gymnastics",
    types: ["gymnastics", "calisthenics", "artistic_gymnastics", "rhythmic_gymnastics", "trampoline_tumbling", "acrobatics", "parkour"],
  },
  { family: "endurance", types: ["aerobics", "running", "cycling", "indoor_cycling", "rowing", "swimming", "endurance"] },
  { family: "mind_body", types: ["yoga", "pilates", "barre", "flexibility", "mobility", "stretching", "tai_chi_qigong"] },
  {
    family: "combat",
    types: [
      "boxing",
      "kickboxing",
      "muay_thai",
      "mma",
      "bjj_grappling",
      "wrestling",
      "martial_arts",
      "self_defense",
      "judo",
      "karate",
      "taekwondo",
      "kung_fu",
      "krav_maga",
    ],
  },
  { family: "dance", types: ["dance", "dance_fitness", "pole_aerial", "ballet", "contemporary_dance", "latin_dance", "street_dance"] },
  { family: "outdoor", types: ["outdoor_training", "climbing_bouldering", "skateboarding"] },
  { family: "recovery", types: ["recovery"] },
] as const;

export type WorkoutTypeFamily = (typeof WORKOUT_TYPE_FAMILIES)[number]["family"];
export type WorkoutType = (typeof WORKOUT_TYPE_FAMILIES)[number]["types"][number];

export const WORKOUT_TYPES: readonly WorkoutType[] = WORKOUT_TYPE_FAMILIES.flatMap((group) => group.types);

const FAMILY_OF = new Map<string, WorkoutTypeFamily>(
  WORKOUT_TYPE_FAMILIES.flatMap((group) => group.types.map((type) => [type, group.family] as const)),
);

export function isWorkoutType(value: unknown): value is WorkoutType {
  return typeof value === "string" && FAMILY_OF.has(value);
}

/** The family of a kind, or null for an unknown one. */
export function workoutTypeFamily(type: string | null | undefined): WorkoutTypeFamily | null {
  return (type && FAMILY_OF.get(type)) || null;
}

/**
 * The families with the kinds a gym offers (`offered`, from its settings),
 * plus `current` when the gym hides it: a workout never loses its kind.
 */
export function offeredWorkoutTypeGroups(offered: readonly string[] | null | undefined, current?: string | null) {
  const allowed = new Set(offered && offered.length > 0 ? offered : WORKOUT_TYPES);
  if (current) allowed.add(current);
  return WORKOUT_TYPE_FAMILIES.map((group) => ({
    family: group.family,
    types: group.types.filter((type) => allowed.has(type)) as WorkoutType[],
  })).filter((group) => group.types.length > 0);
}

/** The families any of `types` belongs to, in catalogue order. */
export function familiesOfWorkoutTypes(types: readonly string[]): WorkoutTypeFamily[] {
  const chosen = new Set(types.map((type) => FAMILY_OF.get(type)));
  return WORKOUT_TYPE_FAMILIES.map((group) => group.family).filter((family) => chosen.has(family));
}

/** Every kind of the given families (a filter by family sends its kinds). */
export function workoutTypesOfFamilies(families: readonly string[]): WorkoutType[] {
  return WORKOUT_TYPE_FAMILIES.filter((group) => families.includes(group.family)).flatMap((group) => group.types);
}
