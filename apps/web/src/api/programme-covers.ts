import { apiRequest } from "@/api/client";
import type { components, operations } from "@/api/generated/schema";
import type { StaffProgramme } from "@/api/programmes";

/**
 * A programme's cover photo (ADR-541): reserve an upload, PUT it to storage,
 * let the API verify it, then set the rendered cover, the original it came
 * from and the edit on the programme. «Αφαίρεση» goes back to the theme strip.
 */
export type ProgrammeCover = components["schemas"]["ProgrammeCover"];
export type ProgrammeCoverInput = components["schemas"]["ProgrammeCoverInput"];
export type ProgrammeCoverUpload =
  operations["PaleeWeb.AdminProgrammeController.cover_upload"]["responses"][200]["content"]["application/json"];
export type ProgrammeCoverMedia =
  operations["PaleeWeb.AdminProgrammeController.complete_cover"]["responses"][200]["content"]["application/json"]["media"];

const id = (value: string) => encodeURIComponent(value);

export function requestProgrammeCoverUpload(token: string, body: { content_type: "image/jpeg" | "image/webp"; byte_size: number }) {
  return apiRequest<ProgrammeCoverUpload>("/admin/programme-covers", { method: "POST", token, body });
}

export async function completeProgrammeCover(token: string, mediaId: string) {
  const data = await apiRequest<{ media: ProgrammeCoverMedia }>(`/admin/programme-covers/${id(mediaId)}/complete`, { method: "POST", token });
  return data.media;
}

export async function setProgrammeCover(token: string, programmeId: string, body: ProgrammeCoverInput) {
  const data = await apiRequest<{ programme: StaffProgramme }>(`/admin/programmes/${id(programmeId)}/cover`, { method: "PUT", token, body });
  return data.programme;
}

export async function removeProgrammeCover(token: string, programmeId: string) {
  const data = await apiRequest<{ programme: StaffProgramme }>(`/admin/programmes/${id(programmeId)}/cover`, { method: "DELETE", token });
  return data.programme;
}
