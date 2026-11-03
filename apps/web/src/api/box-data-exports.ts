import { ApiError, apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

type ExportList =
  paths["/api/org/{organization_slug}/admin/data-exports"]["get"]["responses"]["200"]["content"]["application/json"];

/** ADR-365 / ADR-367: one owner's «Λήψη των δεδομένων του box» request and its files. */
export type BoxDataExport = ExportList["exports"][number];

/** The box's requests, newest first; ready files carry fresh short-lived links. */
export async function fetchBoxDataExports(token: string): Promise<BoxDataExport[]> {
  const response = await apiRequest<ExportList>("/admin/data-exports", { token });
  return response.exports;
}

/** Asks for a new copy of the box's data; it is built in the background. */
export function requestBoxDataExport(token: string): Promise<BoxDataExport> {
  return apiRequest<BoxDataExport>("/admin/data-exports", { method: "POST", token });
}

/** Why a request was refused: one is being prepared, or one was made in the last day. */
export function boxDataExportRefusal(error: unknown): "in_progress" | "too_soon" | null {
  if (!(error instanceof ApiError)) return null;
  if (error.payload.code === "export_in_progress") return "in_progress";
  if (error.payload.code === "box_export_too_soon") return "too_soon";
  return null;
}
