import type { FinanceRecord } from "@/api/finance";
import { ALL_ROLES, type RoleName } from "@/api/roles";

// ADR-812: the roles a finance ledger row shows, filters and sorts by.

/** Client roles first, then staff, each in the hierarchy's order. */
export const LEDGER_ROLE_ORDER: RoleName[] = [
  "member",
  "athlete",
  "guest",
  "owner",
  "admin",
  "coach",
  "front_desk",
  "accountant",
  "janitor",
];

export const BUYER_ROLES: RoleName[] = ["member", "athlete", "guest"];
export const STAFF_ROLES: RoleName[] = ["owner", "admin", "coach", "front_desk", "accountant", "janitor"];

export function orderedRoles(roles: readonly string[]): RoleName[] {
  return LEDGER_ROLE_ORDER.filter((role) => roles.includes(role));
}

/** Every role a ledger row's person holds in the box. */
export function memberRoles(member: FinanceRecord): RoleName[] {
  const roles = Array.isArray(member.roles) ? (member.roles as string[]) : [];
  if (roles.length > 0) return orderedRoles(roles);
  const fallback = typeof member.identity_role === "string" ? member.identity_role : "";
  return ALL_ROLES.includes(fallback as RoleName) ? [fallback as RoleName] : [];
}

/** Sort key: the first role in ledger order (people without roles last). */
export function roleRank(member: FinanceRecord): number {
  const first = memberRoles(member)[0];
  return first ? LEDGER_ROLE_ORDER.indexOf(first) : LEDGER_ROLE_ORDER.length;
}
