import type { FollowSuggestionReason } from "@/api/follow-suggestions";

/** A reason line as a `FollowSuggestions` message key and its values (ADR-561). */
export type ReasonMessage = { key: string; values: Record<string, string | number> };

/**
 * The one line under a suggested person's name. Common follows name up to
 * two people, then «and N more»; `sportLabel` turns a discipline key into
 * its name (null when unknown, then the line stays generic); `seedName` is
 * the profile «Και αυτοί ίσως» sits on.
 */
export function reasonMessage(
  reason: FollowSuggestionReason,
  sportLabel: (key: string) => string | null,
  seedName: string | null = null,
): ReasonMessage {
  const box = reason.box?.name ?? null;
  switch (reason.kind) {
    case "follows_you":
      return { key: "reason.followsYou", values: {} };
    case "mutual": {
      const names = reason.mutuals.map((person) => person.nickname).filter((name): name is string => Boolean(name));
      if (names.length === 0) return { key: "reason.mutualCount", values: { count: reason.mutual_count } };
      return {
        key: "reason.mutual",
        values: { names: names.join(", "), more: Math.max(reason.mutual_count - names.length, 0) },
      };
    }
    case "via_person":
      return seedName ? { key: "reason.viaPerson", values: { name: seedName } } : { key: "reason.forYou", values: {} };
    case "coach":
      return box ? { key: "reason.coach", values: { box } } : { key: "reason.forYou", values: {} };
    case "box":
      return box ? { key: "reason.box", values: { box } } : { key: "reason.forYou", values: {} };
    case "club":
      return reason.club?.name ? { key: "reason.club", values: { club: reason.club.name } } : { key: "reason.forYou", values: {} };
    case "sport": {
      const sport = reason.sport ? sportLabel(reason.sport) : null;
      return sport ? { key: "reason.sport", values: { sport } } : { key: "reason.sports", values: {} };
    }
    case "nearby":
      return { key: "reason.nearby", values: {} };
    case "popular":
      return { key: "reason.popular", values: {} };
    case "newcomer":
      return box ? { key: "reason.newInBox", values: { box } } : { key: "reason.newOnPalee", values: {} };
    default:
      return { key: "reason.forYou", values: {} };
  }
}
