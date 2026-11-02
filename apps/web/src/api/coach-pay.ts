import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

/*
 * «Αμοιβές coaches» (ADR-341, ADR-382): pay rules per person, periods that
 * are calculated, approved and exported, lines added by hand, overtime and
 * allowances, the statements of one staff member and the person's own
 * («Οι αμοιβές μου»). Calls go through the selected gym
 * (`/org/:slug/admin/coach-pay/...`). Pay statements are internal records,
 * never fiscal documents.
 */

type Json<Op extends keyof operations, Code extends number = 200> = operations[Op]["responses"] extends Record<
  Code,
  { content: { "application/json": infer Body } }
>
  ? Body
  : never;

type Body<Op extends keyof operations> =
  NonNullable<operations[Op]["requestBody"]> extends { content: { "application/json": infer Payload } } ? Payload : never;

export type PayRule = Json<"PaleeWeb.AdminCoachPayController.rules">["rules"][number];
export type PayRuleKind = PayRule["kind"];
export type PayRuleBody = Body<"PaleeWeb.AdminCoachPayController.create_rule">;
export type PayRuleUpdate = Body<"PaleeWeb.AdminCoachPayController.update_rule">;
export type PayPeriodSummary = Json<"PaleeWeb.AdminCoachPayController.periods">["periods"][number];
export type PayPeriod = Json<"PaleeWeb.AdminCoachPayController.period">["period"];
export type PayPeriodStatus = PayPeriod["status"];
export type PayStatement = NonNullable<PayPeriod["statements"]>[number];
export type PayLine = PayStatement["lines"][number];
export type PayGroup = PayStatement["groups"][number];
export type PayLineKind = PayLine["kind"];
export type AmountBasis = PayLine["amount_basis"];
export type AdjustmentBody = Body<"PaleeWeb.AdminCoachPayController.add_adjustment">;
export type AdjustmentKind = NonNullable<AdjustmentBody["kind"]>;
export type PayItemLineBody = Body<"PaleeWeb.AdminCoachPayController.add_pay_item_line">;
export type PayItem = Json<"PaleeWeb.AdminCoachPayController.items">["items"][number];
export type PayItemBody = Body<"PaleeWeb.AdminCoachPayController.create_item">;
export type PayItemUpdate = Body<"PaleeWeb.AdminCoachPayController.update_item">;
export type PayRole = PayItem["roles"][number];
export type PersonStatements = Json<"PaleeWeb.AdminCoachPayController.person_statements">;
export type MyPay = Json<"PaleeWeb.MyCoachPayController.index">;
export type MyStatement = MyPay["statements"][number];
export type PayTotals = MyPay["totals"][number];
export type PaySummary = Json<"PaleeWeb.AdminCoachPayController.summary">;

/** The period a statement belongs to, as `GET /coach-pay/mine` and the staff profile return it. */
export type StatementPeriod = { id: string; starts_on: string; ends_on: string; status: PayPeriodStatus; currency: string };

const id = (value: string) => encodeURIComponent(value);
const base = "/admin/coach-pay";

export const coachPayKeys = {
  all: ["admin", "coach-pay"] as const,
  rules: ["admin", "coach-pay", "rules"] as const,
  periods: ["admin", "coach-pay", "periods"] as const,
  period: (periodId: string) => ["admin", "coach-pay", "period", periodId] as const,
  items: ["admin", "coach-pay", "items"] as const,
  person: (userId: string) => ["admin", "coach-pay", "person", userId] as const,
  summary: ["admin", "coach-pay", "summary"] as const,
  mine: ["admin", "coach-pay", "mine"] as const,
};

export function fetchPayRules(token: string, filters: { coach_user_id?: string; include_archived?: boolean } = {}) {
  const query = new URLSearchParams();
  if (filters.coach_user_id) query.set("coach_user_id", filters.coach_user_id);
  if (filters.include_archived) query.set("include_archived", "true");
  const suffix = query.toString();
  return apiRequest<{ rules: PayRule[] }>(`${base}/rules${suffix ? `?${suffix}` : ""}`, { token });
}

export function createPayRule(token: string, body: PayRuleBody) {
  return apiRequest<{ rule: PayRule }>(`${base}/rules`, { method: "POST", token, body });
}

export function updatePayRule(token: string, ruleId: string, body: PayRuleUpdate) {
  return apiRequest<{ rule: PayRule }>(`${base}/rules/${id(ruleId)}`, { method: "PATCH", token, body });
}

export function archivePayRule(token: string, ruleId: string) {
  return apiRequest<{ rule: PayRule }>(`${base}/rules/${id(ruleId)}/archive`, { method: "POST", token });
}

export function fetchPayPeriods(token: string) {
  return apiRequest<{ periods: PayPeriodSummary[] }>(`${base}/periods`, { token });
}

export function createPayPeriod(token: string, body: { starts_on: string; ends_on: string }) {
  return apiRequest<{ period: PayPeriod }>(`${base}/periods`, { method: "POST", token, body });
}

export function fetchPayPeriod(token: string, periodId: string) {
  return apiRequest<{ period: PayPeriod }>(`${base}/periods/${id(periodId)}`, { token });
}

export function calculatePayPeriod(token: string, periodId: string) {
  return apiRequest<{ period: PayPeriod }>(`${base}/periods/${id(periodId)}/calculate`, { method: "POST", token });
}

export function approvePayPeriod(token: string, periodId: string) {
  return apiRequest<{ period: PayPeriod }>(`${base}/periods/${id(periodId)}/approve`, { method: "POST", token });
}

export function reopenPayPeriod(token: string, periodId: string, reason: string) {
  return apiRequest<{ period: PayPeriod }>(`${base}/periods/${id(periodId)}/reopen`, { method: "POST", token, body: { reason } });
}

/** The accountant's CSV; exporting an approved period marks it exported. */
export function exportPayPeriod(token: string, periodId: string) {
  return apiRequest<Blob>(`${base}/periods/${id(periodId)}/export`, { token, responseType: "blob" });
}

export function addPayAdjustment(token: string, periodId: string, body: AdjustmentBody) {
  return apiRequest<{ period: PayPeriod }>(`${base}/periods/${id(periodId)}/adjustments`, { method: "POST", token, body });
}

export function deletePayAdjustment(token: string, periodId: string, lineId: string) {
  return apiRequest<{ period: PayPeriod }>(`${base}/periods/${id(periodId)}/adjustments/${id(lineId)}`, { method: "DELETE", token });
}

export function setPayLineBasis(token: string, periodId: string, lineId: string, basis: AmountBasis) {
  return apiRequest<{ period: PayPeriod }>(`${base}/periods/${id(periodId)}/lines/${id(lineId)}`, {
    method: "PATCH",
    token,
    body: { amount_basis: basis },
  });
}

export function addPayItemLine(token: string, periodId: string, body: PayItemLineBody) {
  return apiRequest<{ period: PayPeriod }>(`${base}/periods/${id(periodId)}/pay-items`, { method: "POST", token, body });
}

/** «Εκκαθαριστικό»: one person's approved statement as PDF. */
export function fetchPayslipPdf(token: string, periodId: string, userId: string, language: string) {
  return apiRequest<Blob>(`${base}/periods/${id(periodId)}/statements/${id(userId)}/pdf?language=${id(language)}`, {
    token,
    responseType: "blob",
  });
}

export function fetchPayItems(token: string, includeArchived = false) {
  return apiRequest<{ items: PayItem[] }>(`${base}/items${includeArchived ? "?include_archived=true" : ""}`, { token });
}

export function createPayItem(token: string, body: PayItemBody) {
  return apiRequest<{ item: PayItem }>(`${base}/items`, { method: "POST", token, body });
}

export function updatePayItem(token: string, itemId: string, body: PayItemUpdate) {
  return apiRequest<{ item: PayItem }>(`${base}/items/${id(itemId)}`, { method: "PATCH", token, body });
}

export function archivePayItem(token: string, itemId: string) {
  return apiRequest<{ item: PayItem }>(`${base}/items/${id(itemId)}/archive`, { method: "POST", token });
}

/** Every statement of one staff member (their profile), with totals per currency. */
export function fetchPersonStatements(token: string, userId: string) {
  return apiRequest<PersonStatements>(`${base}/people/${id(userId)}/statements`, { token });
}

export function fetchPaySummary(token: string, range: { from?: string; to?: string } = {}) {
  const query = new URLSearchParams();
  if (range.from) query.set("from", range.from);
  if (range.to) query.set("to", range.to);
  const suffix = query.toString();
  return apiRequest<PaySummary>(`${base}/summary${suffix ? `?${suffix}` : ""}`, { token });
}

/** «Οι αμοιβές μου»: the caller's own approved statements. */
export function fetchMyPay(token: string) {
  return apiRequest<MyPay>(`${base}/mine`, { token });
}

export function fetchMyPayslipPdf(token: string, periodId: string, language: string) {
  return apiRequest<Blob>(`${base}/mine/${id(periodId)}/pdf?language=${id(language)}`, { token, responseType: "blob" });
}
