import { createPost, type CommunityClub, type CommunityPost, type PostCreate } from "@/api/community";
import { createProfilePost } from "@/api/social";
import { channelName, composeTargetGroups, type ComposeTarget } from "@/components/community/community";

/**
 * Where a post goes and how it gets there, shared by compose and the share
 * card (ADR-142, ADR-565): the last target is remembered per device, and a
 * channel target is published as a club post, a profile target as a
 * profile post.
 */
export const LAST_TARGET_KEY = "palee:compose-target";

export function readStored<T>(key: string): T | null {
  try {
    const raw = window.localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}

export function writeStored(key: string, value: unknown) {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Remembering is a convenience; posting works without it.
  }
}

export function rememberedTarget(): ComposeTarget | null {
  return readStored<ComposeTarget>(LAST_TARGET_KEY);
}

export function rememberTarget(target: ComposeTarget) {
  writeStored(LAST_TARGET_KEY, target);
}

/** The club and channel a channel target points at, if the member may still post there. */
export function channelOf(clubs: CommunityClub[], target: ComposeTarget) {
  if (target.kind !== "channel") return undefined;
  return composeTargetGroups(clubs)
    .flatMap((group) => group.channels.map((channel) => ({ club: group.club, channel })))
    .find((option) => option.channel.id === target.channelId);
}

/** «Milos method › #wod-σήμερα», «Ακόλουθοι», «Δημόσιο». */
export function targetLabel(clubs: CommunityClub[], target: ComposeTarget, t: (key: string, values?: Record<string, string>) => string) {
  if (target.kind === "profile") return target.audience === "public" ? t("audiencePublic") : t("audienceFollowers");
  const option = channelOf(clubs, target);
  if (!option) return "";
  return target.public
    ? t("audienceBoxPublic", { club: option.club.name })
    : `${option.club.name} › #${channelName(option.channel, t)}`;
}

export type PostContent = Omit<PostCreate, "channel_id" | "audience">;

/** Publishes `content` to `target`; null when a channel target is no longer offered. */
export async function publishToTarget(
  token: string,
  clubs: CommunityClub[],
  target: ComposeTarget,
  content: PostContent,
): Promise<CommunityPost | null> {
  if (target.kind === "profile") return createProfilePost(token, { audience: target.audience, ...content });
  const option = channelOf(clubs, target);
  if (!option) return null;
  return createPost(token, {
    channel_id: option.channel.id,
    audience: target.public ? "public" : "club_channel",
    ...content,
  });
}
