import type { FinanceRecord } from "@/api/finance";

/** «Διαθέσιμο»: sold and given by the desk. A retired package is `active: false`. */
export function isAvailable(pkg: FinanceRecord | null | undefined) {
  return pkg?.active !== false;
}

/**
 * How many members hold `packageId` now, per account type (the server's
 * retire step needs a replacement package for each type it finds).
 */
export function holdersByRole(members: FinanceRecord[], packageId: string): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const member of members) {
    const subscription = member.active_package_subscription as FinanceRecord | null | undefined;
    if (String(subscription?.membership_package_id ?? "") !== packageId) continue;
    const membership = member.membership as FinanceRecord | null | undefined;
    const role = String(membership?.user_type_snapshot ?? member.identity_role ?? "");
    if (role) counts[role] = (counts[role] ?? 0) + 1;
  }
  return counts;
}

/** Packages the holders can move to: available ones other than this one. */
export function replacementCandidates(packages: FinanceRecord[], packageId: string) {
  return packages.filter((candidate) => isAvailable(candidate) && String(candidate.id ?? "") !== packageId);
}
