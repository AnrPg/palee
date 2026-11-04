import { membershipRoles, STAFF_ROLES, type MembershipLike } from "@/lib/role-navigation";

/**
 * ADR-463: staff say once, in the first run, whether they also train with
 * Palee (`trains_with_palee` on /auth/me). `false` hides the prompts aimed at
 * athletes (find a box, the sports and area steps, the weekly goal, the
 * «my sports» chip); `null` or a missing field (members, athletes, anyone
 * never asked, older API responses) reads as "trains". Staff tools never
 * depend on it.
 */
export type AthleteUseUser = { trains_with_palee?: boolean | null } | null | undefined;

export function usesAppAsAthlete(user: AthleteUseUser): boolean {
  return user?.trains_with_palee !== false;
}

type StaffMembership = MembershipLike & { organization: { name: string } };

/**
 * The first membership with a staff role and that role (the highest of the
 * membership's staff roles, owner first), for «Μπήκες ως Coach στο <box>».
 * Null for someone who holds no staff role anywhere.
 */
export function firstStaffRole<M extends StaffMembership>(
  memberships: readonly M[] | null | undefined,
): { membership: M; role: (typeof STAFF_ROLES)[number] } | null {
  for (const membership of memberships ?? []) {
    const roles = membershipRoles(membership);
    const role = STAFF_ROLES.find((staffRole) => roles.includes(staffRole));
    if (role) return { membership, role };
  }
  return null;
}
