import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/** ADR-612: «Δώρο ή χάρη», what the box gave a member and who gave it. */
export type MemberBenefit = components["schemas"]["MemberBenefit"];
export type MemberBenefitKind = MemberBenefit["kind"];
export type MemberBenefitGrant = components["schemas"]["MemberBenefitGrant"];

type One = { benefit: MemberBenefit; replayed: boolean };

const path = (userId: string) => `/admin/finance/members/${userId}/benefits`;

export async function fetchMemberBenefits(token: string, userId: string) {
  const response = await apiRequest<{ benefits: MemberBenefit[] }>(path(userId), { token });
  return response.benefits ?? [];
}

export function giveMemberBenefit(token: string, userId: string, body: MemberBenefitGrant) {
  return apiRequest<One>(path(userId), { token, method: "POST", body });
}

export function revokeMemberBenefit(
  token: string,
  userId: string,
  benefitId: string,
  body: { reason: string | null; idempotency_key: string },
) {
  return apiRequest<One>(`${path(userId)}/${benefitId}/revoke`, { token, method: "POST", body });
}
