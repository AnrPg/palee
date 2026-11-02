import type { MemberRisk, RiskAction, RiskReason } from "@/api/leads";

/**
 * «Γιατί»: one plain sentence per reason (ADR-347), from the facts the score
 * read. Returns the message key under `AtRisk.reason.*` and its numbers.
 */
export function reasonLine(reason: Pick<RiskReason, "code" | "facts">): { key: RiskReason["code"]; values: Record<string, number> } {
  const facts = (reason.facts ?? {}) as Record<string, unknown>;
  const num = (key: string) => {
    const value = facts[key];
    return typeof value === "number" && Number.isFinite(value) ? value : 0;
  };
  switch (reason.code) {
    case "attendance_drop":
      return { key: reason.code, values: { now: num("per_week_now"), usual: num("per_week_usual") } };
    case "absent":
    case "package_ending":
      return { key: reason.code, values: { days: num("days") } };
    case "no_first_visit":
      return { key: reason.code, values: { days: num("member_for_days") } };
    case "no_upcoming_bookings":
      return { key: reason.code, values: { days: num("days_ahead") } };
    case "payment_overdue":
      return { key: reason.code, values: { count: num("invoices") } };
    case "many_cancellations":
      return { key: reason.code, values: { count: num("cancellations") } };
    case "new_member_slow_start":
      return { key: reason.code, values: { days: num("member_for_days"), visits: num("visits") } };
  }
}

/** The reasons that weigh most first; the score itself is never shown (ADR-347). */
export function sortedReasons(member: Pick<MemberRisk, "reasons">): RiskReason[] {
  return [...member.reasons].sort((a, b) => b.points - a.points);
}

/** Whether staff already reached the member since their current level started. */
export function contactedThisSpell(member: Pick<MemberRisk, "contacted_at" | "level_since">): boolean {
  if (!member.contacted_at) return false;
  return new Date(member.contacted_at).getTime() >= new Date(member.level_since).getTime();
}

/** The «Αργότερα» choices, in days (the API takes 1 to 90). */
export const SNOOZE_DAYS = [3, 7, 14, 30] as const;

/** The message key of one log line under `AtRisk.action.*`. */
export function actionKey(action: Pick<RiskAction, "kind">): "contacted" | "snoozed" | "unsnoozed" {
  return action.kind;
}

/** A display name for a person of the API, or null. */
export function personName(person: { display_name?: string | null; handle?: string | null } | null | undefined): string | null {
  return person?.display_name?.trim() || person?.handle?.trim() || null;
}
