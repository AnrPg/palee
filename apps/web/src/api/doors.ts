import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/*
 * Doors (ADR-381, ontology §4.28): Ρυθμίσεις › Παραρτήματα › <branch> ›
 * «Πόρτες», «Άνοιγμα» from the desk, the access log («Ημερολόγιο εισόδων»)
 * and the member's door opening after the door scan. Controller keys are
 * written, never read back.
 */
type Schemas = components["schemas"];

export type Door = Schemas["Door"];
export type DoorProvider = Door["provider"];
export type DoorCatalog = Schemas["DoorCatalog"];
export type DoorWithEventUrl = Schemas["DoorWithEventUrl"];
export type AccessEvent = Schemas["AccessEvent"];
export type AccessEventPage = Schemas["AccessEventPage"];
export type DoorOpenRequest = Schemas["DoorOpenRequest"];
export type DoorOpenResult = Schemas["DoorOpenResult"];

export type DoorWho = "booked_or_covered" | "members" | "staff_only";
export type DoorPeriod = { days: number[]; from: string; to: string };
export type DoorRules = {
  who: DoorWho;
  staff_always: boolean;
  window_before_minutes: number;
  window_after_minutes: number;
  unlock_seconds: number;
  hours: DoorPeriod[];
};

export const DOOR_CATALOG_KEY = ["admin", "doors", "catalog"] as const;
export const doorsKey = (locationId?: string) => ["admin", "doors", locationId ?? "all"] as const;
export const accessEventsKey = (filters: AccessEventFilters) => ["admin", "access-events", filters] as const;

const id = (value: string) => encodeURIComponent(value);

export function fetchDoorCatalog(token: string) {
  return apiRequest<DoorCatalog>("/admin/doors/catalog", { token });
}

export async function fetchDoors(token: string, locationId?: string) {
  const query = locationId ? `?location_id=${id(locationId)}` : "";
  return (await apiRequest<{ doors: Door[] }>(`/admin/doors${query}`, { token })).doors;
}

export type DoorBody = {
  name: string;
  location_id: string;
  provider: DoorProvider;
  settings?: Record<string, unknown>;
  credentials?: Record<string, unknown>;
  rules?: Partial<DoorRules>;
};

export function createDoor(token: string, body: DoorBody) {
  return apiRequest<DoorWithEventUrl>("/admin/doors", { method: "POST", token, body });
}

export async function updateDoor(
  token: string,
  doorId: string,
  body: { name?: string; settings?: Record<string, unknown>; credentials?: Record<string, unknown>; rules?: Partial<DoorRules>; status?: "active" | "disabled" },
) {
  return (await apiRequest<{ door: Door }>(`/admin/doors/${id(doorId)}`, { method: "PATCH", token, body })).door;
}

export function deleteDoor(token: string, doorId: string) {
  return apiRequest<{ ok: boolean }>(`/admin/doors/${id(doorId)}`, { method: "DELETE", token });
}

export async function rotateDoorEventUrl(token: string, doorId: string) {
  return (await apiRequest<{ event_url: string }>(`/admin/doors/${id(doorId)}/event-token`, { method: "POST", token })).event_url;
}

/** «Άνοιγμα» from the desk: logged with who opened it. */
export async function unlockDoor(token: string, doorId: string) {
  return (await apiRequest<{ opened: boolean }>(`/admin/doors/${id(doorId)}/unlock`, { method: "POST", token })).opened;
}

export type AccessEventFilters = { door_id?: string; location_id?: string; kind?: AccessEvent["kind"]; limit?: number; offset?: number };

export function fetchAccessEvents(token: string, filters: AccessEventFilters = {}) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(filters)) {
    if (value !== undefined && value !== null && value !== "") search.set(key, String(value));
  }
  const query = search.toString();
  return apiRequest<AccessEventPage>(`/admin/access-events${query ? `?${query}` : ""}`, { token });
}

/** The member's door opening, with the same proof of presence as the check-in scan. */
export function openDoor(token: string, body: DoorOpenRequest) {
  return apiRequest<DoorOpenResult>("/access/open", { method: "POST", token, body });
}
