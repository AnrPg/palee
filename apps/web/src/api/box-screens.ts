import { ApiError, apiRequest, type ApiErrorPayload } from "@/api/client";
import type { ClassTimerPayload } from "@/api/class-timers";
import type { components } from "@/api/generated/schema";

// ADR-253: the box screen («Οθόνη box»). Staff manage screens under
// /admin/box-screens with their session; the TV itself pairs with a code and
// then uses only its display token on /api/box-screen/*.

type Schemas = components["schemas"];

export type BoxScreen = Schemas["BoxScreen"];
export type BoxScreenOverride = NonNullable<Schemas["BoxScreenOverride"]>;
export type BoxScreenOverrideView = BoxScreenOverride["view"];
export type BoxScreenPairingCode = Schemas["BoxScreenPairingCode"];
export type BoxScreenToday = Schemas["BoxScreenToday"];
export type BoxScreenClass = BoxScreenToday["classes"][number];
export type BoxScreenFocus = BoxScreenToday["focus"];
export type BoxScreenLeaderboard = BoxScreenToday["leaderboards"][number];
export type BoxScreenWorkout = BoxScreenToday["workouts"][number];

export type BoxScreenList = { screens: BoxScreen[]; max_screens: number; override_views: BoxScreenOverrideView[] };
export type BoxScreenWithCode = { screen: BoxScreen; pairing_code: BoxScreenPairingCode };
export type BoxScreenOverrideInput = { view: BoxScreenOverrideView; slot_id?: string | null; until?: string | null };

export const BOX_SCREENS_KEY = ["admin", "box-screens"] as const;

export function listBoxScreens(token: string) {
  return apiRequest<BoxScreenList>("/admin/box-screens", { token });
}

export function createBoxScreen(token: string, input: { name: string; location_id: string | null }) {
  return apiRequest<BoxScreenWithCode>("/admin/box-screens", { method: "POST", token, body: input });
}

export function updateBoxScreen(
  token: string,
  id: string,
  input: { name?: string; location_id?: string | null; space_id?: string | null; concurrent_mode?: "room" | "split" },
) {
  return apiRequest<{ screen: BoxScreen }>(`/admin/box-screens/${id}`, { method: "PATCH", token, body: input });
}

export function deleteBoxScreen(token: string, id: string) {
  return apiRequest<void>(`/admin/box-screens/${id}`, { method: "DELETE", token });
}

export function newBoxScreenPairingCode(token: string, id: string) {
  return apiRequest<BoxScreenWithCode>(`/admin/box-screens/${id}/pairing-code`, { method: "POST", token, body: {} });
}

export function pinBoxScreen(token: string, id: string, input: BoxScreenOverrideInput) {
  return apiRequest<{ screen: BoxScreen }>(`/admin/box-screens/${id}/override`, { method: "PUT", token, body: input });
}

export function unpinBoxScreen(token: string, id: string) {
  return apiRequest<{ screen: BoxScreen }>(`/admin/box-screens/${id}/override`, { method: "DELETE", token });
}

// --- «Στην οθόνη»: one class, from its timer remote (ADR-253 update) --------
// The class's own coach (today, screens of the class's branch or the whole
// box) pins its timer, leaderboard or WOD; the API decides who may.

export type ClassScreenList = Schemas["ClassScreenList"];
export type ClassScreenInput = {
  view: BoxScreenOverrideView;
  until?: string | null;
  /** ADR-746: one of the class's WODs; null follows its «Τώρα». */
  workout_id?: string | null;
  /** ADR-746: share the screen with a class that runs at the same time. */
  split_slot_id?: string | null;
};

export const classScreensKey = (slotId: string) => ["class-timers", slotId, "screens"] as const;

export function listClassScreens(token: string, slotId: string) {
  return apiRequest<ClassScreenList>(`/class-timers/${slotId}/screens`, { token });
}

export function pinClassScreen(token: string, slotId: string, screenId: string, input: ClassScreenInput) {
  // ADR-746: no WOD or shared class is the same as leaving them out.
  const body = Object.fromEntries(Object.entries(input).filter(([, value]) => value !== null && value !== undefined));
  return apiRequest<{ screen: BoxScreen }>(`/class-timers/${slotId}/screens/${screenId}/override`, { method: "PUT", token, body });
}

export function unpinClassScreen(token: string, slotId: string, screenId: string) {
  return apiRequest<{ screen: BoxScreen }>(`/class-timers/${slotId}/screens/${screenId}/override`, { method: "DELETE", token });
}

// --- The TV ---------------------------------------------------------------
// Plain fetch on purpose: the display token is not a session, so the
// session's refresh-on-401 and organization scoping must never touch it.

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "/api";

export type BoxScreenPairing = {
  token: string;
  expires_at: string;
  screen: { id: string; name: string };
  box: { id: string; name: string };
};

async function screenRequest<T>(path: string, init: { method?: "GET" | "POST"; token?: string; body?: unknown }): Promise<T> {
  const response = await fetch(`${API_BASE_URL}/box-screen${path}`, {
    method: init.method ?? "GET",
    headers: {
      "Content-Type": "application/json",
      ...(init.token ? { Authorization: `Bearer ${init.token}` } : {}),
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
    credentials: "omit",
  });
  const payload = (await response.json().catch(() => ({}))) as unknown;
  if (!response.ok) {
    const error = (payload ?? {}) as ApiErrorPayload;
    throw new ApiError(response.status, error.error ?? `HTTP ${response.status}`, error);
  }
  return payload as T;
}

export function pairBoxScreen(code: string) {
  return screenRequest<BoxScreenPairing>("/pair", { method: "POST", body: { code } });
}

export function renewBoxScreenToken(token: string) {
  return screenRequest<{ token: string; expires_at: string }>("/token", { method: "POST", token });
}

export function fetchBoxScreenToday(token: string) {
  return screenRequest<BoxScreenToday>("/today", { token });
}

/** ADR-746: `workoutId` picks one of the class's WODs; without it, the class's «Τώρα». */
export function fetchBoxScreenTimer(token: string, slotId: string, workoutId?: string | null) {
  const query = workoutId ? `?workout_id=${encodeURIComponent(workoutId)}` : "";
  return screenRequest<ClassTimerPayload>(`/classes/${slotId}/timer${query}`, { token });
}

/** The display token no longer opens anything: the screen was removed or moved to another TV. */
export function isScreenTokenRejected(error: unknown) {
  return error instanceof ApiError && error.status === 401;
}
