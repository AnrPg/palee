import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

/**
 * Leads and retention (ADR-344..347, ADR-384): «Ενδιαφερόμενοι» with their
 * history and next steps, the ready «Αυτοματισμοί», «Σε κίνδυνο» with the
 * staff action log, the member's «Αυτόματα μηνύματα» and the public
 * «Ενδιαφέρομαι» form. Staff calls go through the selected box (`/admin`).
 */

type Json<Op extends keyof operations, Status extends number = 200> = operations[Op] extends {
  responses: { [S in Status]: { content: { "application/json": infer Body } } };
}
  ? Body
  : never;

type RequestJson<Op extends keyof operations> = operations[Op] extends {
  requestBody?: { content: { "application/json": infer Body } };
}
  ? Body
  : never;

// Leads ----------------------------------------------------------------------

export type LeadList = Json<"PaleeWeb.AdminLeadController.index">;
export type Lead = LeadList["leads"][number];
export type LeadDetail = Json<"PaleeWeb.AdminLeadController.show">;
export type LeadEvent = LeadDetail["events"][number];
export type LeadTask = LeadDetail["tasks"][number];
export type LeadStage = Lead["stage"];
export type LeadSource = Lead["source"];
export type LostReason = NonNullable<Lead["lost_reason"]>;
export type LeadPerson = NonNullable<Lead["owner"]>;
export type LeadCreate = RequestJson<"PaleeWeb.AdminLeadController.create">;
export type LeadUpdate = RequestJson<"PaleeWeb.AdminLeadController.update">;
export type LeadImportResult = Json<"PaleeWeb.AdminLeadController.import">;
export type ContactChannel = NonNullable<RequestJson<"PaleeWeb.AdminLeadController.contacted">["channel"]>;

export const OPEN_STAGES = ["new", "trial", "offer"] as const satisfies readonly LeadStage[];
export const CLOSED_STAGES = ["converted", "lost"] as const satisfies readonly LeadStage[];
export const LOST_REASONS = [
  "price",
  "schedule",
  "location",
  "no_answer",
  "chose_other",
  "not_interested",
  "other",
] as const satisfies readonly LostReason[];
export const STAFF_SOURCES = ["walk_in", "manual", "referral", "event"] as const;
export type StaffSource = (typeof STAFF_SOURCES)[number];
export const CONTACT_CHANNELS = ["phone", "email", "message", "in_person"] as const satisfies readonly ContactChannel[];

export const LEADS_KEY = ["admin", "leads"] as const;
export const leadsKey = (stage: string) => ["admin", "leads", "list", stage] as const;
export const leadKey = (id: string) => ["admin", "leads", "detail", id] as const;

const lead = (id: string) => `/admin/leads/${encodeURIComponent(id)}`;

export function fetchLeads(token: string, params: { stage?: string; q?: string; limit?: number } = {}) {
  const query = new URLSearchParams();
  if (params.stage) query.set("stage", params.stage);
  if (params.q) query.set("q", params.q);
  query.set("limit", String(params.limit ?? 200));
  return apiRequest<LeadList>(`/admin/leads?${query.toString()}`, { token });
}

export function fetchLead(token: string, id: string) {
  return apiRequest<LeadDetail>(lead(id), { token });
}

export function createLead(token: string, body: LeadCreate) {
  return apiRequest<LeadDetail>("/admin/leads", { method: "POST", token, body });
}

export function updateLead(token: string, id: string, body: LeadUpdate) {
  return apiRequest<LeadDetail>(lead(id), { method: "PATCH", token, body });
}

export function moveLead(token: string, id: string, stage: Exclude<LeadStage, "converted">, lostReason?: LostReason) {
  return apiRequest<LeadDetail>(`${lead(id)}/move`, {
    method: "POST",
    token,
    body: lostReason ? { stage, lost_reason: lostReason } : { stage },
  });
}

export function addLeadNote(token: string, id: string, text: string) {
  return apiRequest<LeadDetail>(`${lead(id)}/notes`, { method: "POST", token, body: { text } });
}

export function markLeadContacted(token: string, id: string, channel: ContactChannel) {
  return apiRequest<LeadDetail>(`${lead(id)}/contacted`, { method: "POST", token, body: { channel } });
}

export function addLeadTask(token: string, id: string, body: { title: string; due_at: string; assignee_id?: string }) {
  return apiRequest<LeadDetail>(`${lead(id)}/tasks`, { method: "POST", token, body });
}

export function completeLeadTask(token: string, taskId: string) {
  return apiRequest<LeadDetail>(`/admin/leads/tasks/${encodeURIComponent(taskId)}/done`, { method: "POST", token });
}

export function convertLead(token: string, id: string, userId: string) {
  return apiRequest<LeadDetail>(`${lead(id)}/convert`, { method: "POST", token, body: { user_id: userId } });
}

export function optOutLead(token: string, id: string) {
  return apiRequest<LeadDetail>(`${lead(id)}/opt-out`, { method: "POST", token });
}

export function importLeads(token: string, csv: string, dryRun: boolean) {
  return apiRequest<LeadImportResult>("/admin/leads/import", { method: "POST", token, body: { csv, dry_run: dryRun } });
}

// Automations ------------------------------------------------------------------

export type RecipeList = Json<"PaleeWeb.AdminAutomationController.index">;
export type Recipe = RecipeList["recipes"][number];
export type RecipeKey = Recipe["key"];
export type RecipeUpdate = RequestJson<"PaleeWeb.AdminAutomationController.update">;
export type RecipePreview = Json<"PaleeWeb.AdminAutomationController.preview">;
export type Delivery = Json<"PaleeWeb.AdminAutomationController.deliveries">["deliveries"][number];

export const RECIPE_KEYS = [
  "welcome",
  "trial_follow_up",
  "missed_classes",
  "renewal_reminder",
  "birthday",
  "win_back",
] as const satisfies readonly RecipeKey[];

export const automationsKey = (locale: string) => ["admin", "automations", locale] as const;
export const AUTOMATION_MESSAGES_KEY = ["admin", "automations", "messages"] as const;

export function fetchAutomations(token: string, locale: string) {
  return apiRequest<RecipeList>(`/admin/automations?locale=${encodeURIComponent(locale)}`, { token });
}

export async function updateAutomation(token: string, key: RecipeKey, locale: string, body: RecipeUpdate) {
  const data = await apiRequest<{ recipe: Recipe }>(`/admin/automations/${key}?locale=${encodeURIComponent(locale)}`, {
    method: "PATCH",
    token,
    body,
  });
  return data.recipe;
}

export function previewAutomation(
  token: string,
  key: RecipeKey,
  body: { locale: string; first_name?: string; subject?: string; body?: string },
) {
  return apiRequest<RecipePreview>(`/admin/automations/${key}/preview`, { method: "POST", token, body });
}

export async function fetchAutomationMessages(token: string, limit = 50) {
  const data = await apiRequest<{ deliveries: Delivery[] }>(`/admin/automations/messages?limit=${limit}`, { token });
  return data.deliveries;
}

// Members at risk ----------------------------------------------------------------

export type RiskList = Json<"PaleeWeb.AdminMemberRiskController.index">;
export type MemberRisk = RiskList["members"][number];
export type RiskReason = MemberRisk["reasons"][number];
export type RiskDetail = Json<"PaleeWeb.AdminMemberRiskController.show">;
export type RiskAction = RiskDetail["actions"][number];
export type RiskFilter = "all" | "high" | "medium";

export const AT_RISK_KEY = ["admin", "members-at-risk"] as const;
export const atRiskKey = (level: RiskFilter) => ["admin", "members-at-risk", "list", level] as const;
export const atRiskMemberKey = (userId: string) => ["admin", "members-at-risk", "member", userId] as const;

const risk = (userId: string) => `/admin/members-at-risk/${encodeURIComponent(userId)}`;

export function fetchMembersAtRisk(token: string, level: RiskFilter = "all", limit = 100) {
  return apiRequest<RiskList>(`/admin/members-at-risk?level=${level}&limit=${limit}`, { token });
}

export function fetchMemberAtRisk(token: string, userId: string) {
  return apiRequest<RiskDetail>(risk(userId), { token });
}

export async function markMemberContacted(token: string, userId: string, channel: ContactChannel) {
  const data = await apiRequest<{ member: MemberRisk }>(`${risk(userId)}/contacted`, { method: "POST", token, body: { channel } });
  return data.member;
}

export async function snoozeMember(token: string, userId: string, days: number) {
  const data = await apiRequest<{ member: MemberRisk }>(`${risk(userId)}/snooze`, { method: "POST", token, body: { days } });
  return data.member;
}

// The member's «Αυτόματα μηνύματα» --------------------------------------------------

export type AutomaticMessages = Json<"PaleeWeb.MyAutomationPreferencesController.show">;
export type AutomaticMessagesUpdate = RequestJson<"PaleeWeb.MyAutomationPreferencesController.update">;

export const MY_AUTOMATIC_MESSAGES_KEY = ["me", "automatic-messages"] as const;

export function fetchMyAutomaticMessages(token: string) {
  return apiRequest<AutomaticMessages>("/me/automatic-messages", { token });
}

export function updateMyAutomaticMessages(token: string, body: AutomaticMessagesUpdate) {
  return apiRequest<AutomaticMessages>("/me/automatic-messages", { method: "PUT", token, body });
}

// The public «Ενδιαφέρομαι» form (ADR-345) -----------------------------------------

export type LeadEnquiry = RequestJson<"PaleeWeb.PublicLeadController.create">;

/** The version of the consent texts the form shows; stored with the lead. */
export const ENQUIRY_CONSENT_VERSION = "2027-05";

export function sendEnquiry(slug: string, body: LeadEnquiry) {
  return apiRequest<{ status: "received" }>(`/public/boxes/${encodeURIComponent(slug)}/leads`, {
    method: "POST",
    body,
    scope: "account",
  });
}
