// ADR-552: becoming a box member without the member join link. Buying a
// package the box lists to everyone admits the person (`joinToBuy`); anyone
// else asks («Ζήτα να γίνεις μέλος») and the box's staff accept or decline.
import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";
import type { OrganizationMembership } from "@/api/organizations";

export type MyJoinRequest = components["schemas"]["MyJoinRequest"];
export type StaffJoinRequest = components["schemas"]["StaffJoinRequest"];

const id = (value: string) => encodeURIComponent(value);

export const myJoinRequestKey = (slug: string) => ["me", "join-request", slug] as const;
export const STAFF_JOIN_REQUESTS_KEY = ["admin", "join-requests"] as const;

/** Becomes a box member to buy `packageId`, which the box lists to everyone. */
export function joinToBuy(token: string, slug: string, packageId: string) {
  return apiRequest<OrganizationMembership>(`/memberships/join/${id(slug)}/package/${id(packageId)}`, {
    token,
    method: "POST",
  });
}

export function fetchMyJoinRequest(token: string, slug: string) {
  return apiRequest<{ request: MyJoinRequest | null }>(`/boxes/${id(slug)}/join-request`, { token });
}

/** Asks the box; asking again returns the open request. */
export function askToJoin(token: string, slug: string) {
  return apiRequest<{ request: MyJoinRequest }>(`/boxes/${id(slug)}/join-request`, { token, method: "POST" });
}

export function cancelJoinRequest(token: string, slug: string) {
  return apiRequest<{ request: MyJoinRequest }>(`/boxes/${id(slug)}/join-request/cancel`, { token, method: "POST" });
}

export function fetchStaffJoinRequests(token: string) {
  return apiRequest<{ requests: StaffJoinRequest[] }>("/admin/join-requests", { token });
}

export function decideJoinRequest(token: string, requestId: string, decision: "accept" | "decline") {
  return apiRequest<{ request: StaffJoinRequest }>(`/admin/join-requests/${id(requestId)}/${decision}`, {
    token,
    method: "POST",
  });
}
