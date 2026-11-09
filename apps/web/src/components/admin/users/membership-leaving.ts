/** ADR-220/595: staff ending a box membership. */

/**
 * ADR-595: staff end a box membership under the member's own rules: it ends
 * now, a package in force stays usable to its last day, money owed and a
 * minimum commitment's months stay owed. Only the reason is staff's to add.
 */
export function leaveRequest(reason: string): { reason: string | null } {
  return { reason: reason.trim() || null };
}

/** Running packages whose renewal is the box member's choice (`auto_renew` is a boolean). */
export function renewableSubscriptions(subscriptions: Array<Record<string, unknown>>) {
  return subscriptions.filter((subscription) => subscription.status === "active" && typeof subscription.auto_renew === "boolean");
}
