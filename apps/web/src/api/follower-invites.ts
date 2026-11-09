// ADR-580: a box invites the people who follow it to become box members,
// one at a time or many at once. Staff read the followers who are not box
// members and send; the person sees the invitation on the box page and may
// answer «Όχι, ευχαριστώ».
import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

export type BoxFollower = components["schemas"]["BoxFollower"];
export type BoxFollowerList = components["schemas"]["BoxFollowerList"];
export type FollowerInviteCounts = components["schemas"]["FollowerInviteCounts"];
export type FollowerInviteOffer = components["schemas"]["FollowerInviteOffer"];
export type FollowerInviteSendRequest = components["schemas"]["FollowerInviteSendRequest"];
export type FollowerInviteSendResponse = components["schemas"]["FollowerInviteSendResponse"];
export type MyFollowerInvite = NonNullable<components["schemas"]["MyFollowerInviteResponse"]["invite"]>;
export type FollowerFilter = "all" | "trial" | "former";

/** One send takes at most this many people (FollowerInvitePolicy). */
export const FOLLOWER_INVITE_BATCH_MAX = 200;
/** The box's message is at most this long (FollowerInvitePolicy). */
export const FOLLOWER_INVITE_MESSAGE_MAX = 500;

export const FOLLOWER_INVITES_KEY = ["admin", "follower-invites"] as const;
export const FOLLOWER_INVITES_SUMMARY_KEY = [...FOLLOWER_INVITES_KEY, "summary"] as const;
export const followerInvitesListKey = (filter: FollowerFilter) => [...FOLLOWER_INVITES_KEY, "list", filter] as const;
export const myFollowerInviteKey = (slug: string) => ["me", "follower-invite", slug] as const;

const id = (value: string) => encodeURIComponent(value);

export function fetchFollowerInviteSummary(token: string) {
  return apiRequest<{ counts: FollowerInviteCounts }>("/admin/follower-invites/summary", { token });
}

export function fetchBoxFollowers(token: string, filter: FollowerFilter, cursor?: string | null) {
  const query = new URLSearchParams({ filter });
  if (cursor) query.set("cursor", cursor);
  return apiRequest<BoxFollowerList>(`/admin/follower-invites?${query.toString()}`, { token });
}

export function inviteFollowers(token: string, body: FollowerInviteSendRequest) {
  return apiRequest<FollowerInviteSendResponse>("/admin/follower-invites", { token, method: "POST", body });
}

/** A malformed answer reads as «no invitation» (null), never undefined. */
export async function fetchMyFollowerInvite(token: string, slug: string): Promise<MyFollowerInvite | null> {
  const body = await apiRequest<{ invite?: MyFollowerInvite | null } | null>(`/boxes/${id(slug)}/follower-invite`, { token });
  return body?.invite ?? null;
}

export function declineFollowerInvite(token: string, slug: string) {
  return apiRequest<{ invite: null }>(`/boxes/${id(slug)}/follower-invite/decline`, { token, method: "POST" });
}
