import type { FinanceRecord } from "@/api/finance";
import type { MemberBenefit, MemberBenefitGrant, MemberBenefitKind } from "@/api/member-benefits";

/**
 * ADR-612: «Δώρο ή χάρη». The rules the sheet follows before it asks the
 * server: nothing is picked for staff, each kind needs its own answers, and
 * the reason stays optional (at most 500 characters).
 */

export const BENEFIT_KINDS: MemberBenefitKind[] = ["grace", "free_access", "extra_uses", "package", "debt_forgiven"];
export const BENEFIT_PERIODS = ["calendar_week", "calendar_month", "subscription_period"] as const;
export type BenefitPeriod = (typeof BENEFIT_PERIODS)[number];
export const REASON_MAX = 500;

const OPEN_INVOICE_STATUSES = ["issued", "partially_paid", "overdue"];

export type BenefitDraft = {
  kind: MemberBenefitKind | null;
  ends_on: string;
  allowance: string;
  quantity: number;
  period: BenefitPeriod | "";
  package_id: string;
  pricing: "this_period_free" | "price" | "";
  price: string;
  invoice_ids: string[];
  reason: string;
};

export const EMPTY_DRAFT: BenefitDraft = {
  kind: null,
  ends_on: "",
  allowance: "",
  quantity: 1,
  period: "",
  package_id: "",
  pricing: "",
  price: "",
  invoice_ids: [],
  reason: "",
};

function iso(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function parse(day: string) {
  const [year, month, date] = day.slice(0, 10).split("-").map(Number);
  return new Date(year, month - 1, date);
}

/** Quick picks for the last day: a week from today, and the month's last day. */
export function endPresets(today: string) {
  const week = parse(today);
  week.setDate(week.getDate() + 7);
  const start = parse(today);
  const monthEnd = new Date(start.getFullYear(), start.getMonth() + 1, 0);
  return { week: iso(week), monthEnd: iso(monthEnd) };
}

/** "12,50" or "12.50" euros as cents; null when it is not an amount. */
export function priceCents(text: string): number | null {
  const cleaned = text.trim().replace(",", ".");
  if (!/^\d+(\.\d{1,2})?$/.test(cleaned)) return null;
  return Math.round(Number(cleaned) * 100);
}

/** Charges with something still owed on them, oldest first. */
export function openInvoices(invoices: FinanceRecord[]) {
  return invoices
    .filter((invoice) => OPEN_INVOICE_STATUSES.includes(String(invoice.status)) && Number(invoice.balance_due_cents ?? 0) > 0)
    .sort((a, b) => String(a.due_date ?? "").localeCompare(String(b.due_date ?? "")));
}

/** Whether every answer the chosen kind needs is there. */
export function draftReady(draft: BenefitDraft, today: string) {
  if (draft.reason.length > REASON_MAX) return false;
  switch (draft.kind) {
    case "grace":
    case "free_access":
      return draft.ends_on !== "" && draft.ends_on >= today;
    case "extra_uses":
      return draft.allowance !== "" && draft.quantity >= 1 && draft.period !== "";
    case "package":
      return draft.package_id !== "" && (draft.pricing === "this_period_free" || (draft.pricing === "price" && priceCents(draft.price) !== null));
    case "debt_forgiven":
      return draft.invoice_ids.length > 0;
    default:
      return false;
  }
}

/** The request body for a ready draft. */
export function grantBody(draft: BenefitDraft, idempotencyKey: string): MemberBenefitGrant {
  const reason = draft.reason.trim() || null;
  const base = { kind: draft.kind!, reason, idempotency_key: idempotencyKey };
  switch (draft.kind) {
    case "grace":
    case "free_access":
      return { ...base, ends_on: draft.ends_on };
    case "extra_uses":
      return { ...base, allowance: draft.allowance, quantity: draft.quantity, period: draft.period as BenefitPeriod };
    case "package":
      return {
        ...base,
        package_id: draft.package_id,
        pricing: draft.pricing === "price" ? { mode: "price", price_cents: priceCents(draft.price) ?? 0 } : { mode: "this_period_free" },
      };
    default:
      return { ...base, invoice_ids: draft.invoice_ids };
  }
}

/** Grace, free access and extra uses can be taken back while they still count. */
export function revocable(benefit: MemberBenefit) {
  return ["grace", "free_access", "extra_uses"].includes(benefit.kind) && (benefit.state === "active" || benefit.state === "upcoming");
}

export function detail<T>(benefit: MemberBenefit, key: string): T | undefined {
  return (benefit.details as Record<string, unknown> | undefined)?.[key] as T | undefined;
}
