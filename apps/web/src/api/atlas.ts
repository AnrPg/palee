import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";
import type { AtlasRange } from "@/lib/anatomy/atlas";

/**
 * The anatomy atlas (ADR-164): the member's own muscle coverage across every
 * provider (account read model) and, for one node, the exercises that train
 * it with the current gym's videos.
 */
export type MyAtlas = components["schemas"]["MyAtlas"];
export type AtlasNodeCoverage = components["schemas"]["AtlasNodeCoverage"];
export type AtlasNodeExercises = components["schemas"]["AtlasNodeExercises"];
export type AtlasNodeExercise = components["schemas"]["AtlasNodeExercise"];

export const myAtlasKey = (range: AtlasRange) => ["me", "atlas", range] as const;
export const atlasNodeExercisesKey = (nodeId: string) => ["anatomy", "nodes", nodeId, "exercises"] as const;

export function fetchMyAtlas(token: string, range: AtlasRange) {
  return apiRequest<MyAtlas>(`/me/atlas?range=${encodeURIComponent(range)}`, { token, scope: "account" });
}

/** Org-scoped: the gym the member is looking at (the selected provider). */
export function fetchAtlasNodeExercises(token: string, nodeId: string) {
  return apiRequest<AtlasNodeExercises>(`/anatomy/nodes/${encodeURIComponent(nodeId)}/exercises`, { token });
}

/** ADR-670: a client's coverage for their coach, from what they share with this gym. */
export const clientAtlasKey = (userId: string, range: AtlasRange) => ["staff", "clients", userId, "atlas", range] as const;

/** Tenant-scoped: the gym the coach is working in. */
export function fetchClientAtlas(token: string, userId: string, range: AtlasRange) {
  return apiRequest<MyAtlas>(`/staff/clients/${encodeURIComponent(userId)}/atlas?range=${encodeURIComponent(range)}`, { token });
}

/** ADR-670 «Φορτίο προγράμματος»: what the same class worked in the previous 7 days. */
export type ClassProgrammeLoad = components["schemas"]["ClassProgrammeLoad"];
export type ProgrammeLoadGroup = components["schemas"]["ProgrammeLoadGroup"];

export const classProgrammeLoadKey = (classId: string) => ["admin", "schedule", "slots", classId, "programme-load"] as const;

export function fetchClassProgrammeLoad(token: string, classId: string) {
  return apiRequest<ClassProgrammeLoad>(`/admin/schedule/slots/${encodeURIComponent(classId)}/programme-load`, { token });
}
