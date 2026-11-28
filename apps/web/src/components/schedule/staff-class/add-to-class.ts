import { can, type MembershipLike } from "@/lib/role-navigation";

/**
 * ADR-790 (ANR pick δ): who sees «+ Προσθήκη» on a class, as the server's
 * ClassPlacementAccess decides it: staff who book for clients or manage the
 * schedule; a head coach (`run_classes: "all"`); a coach in the classes they
 * run. While the membership is still loading the button stays hidden.
 */
export function mayAddToClass(
  membership: MembershipLike | null | undefined,
  slot: { coach_user_id?: string | null },
  userId: string | null | undefined,
): boolean {
  if (!membership) return false;
  if (can(membership, "book_for_clients") || can(membership, "manage_schedule")) return true;
  const runs = membership.capabilities?.run_classes;
  if (runs === "all") return true;
  return Boolean(runs && userId && slot.coach_user_id === userId);
}
