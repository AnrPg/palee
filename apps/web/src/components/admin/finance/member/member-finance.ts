import type { FinanceRecord } from "@/api/finance";
import type { MemberBenefit } from "@/api/member-benefits";

/**
 * ADR-784: one place for a person's money, shown alike on their profile
 * («Οικονομικά») and in the ledger's side panel. These are the pure parts:
 * what is owed, the next charge and one dated list of movements (charges,
 * payments, refunds, gifts and credits) that the screen filters and colours.
 */

export const MOVEMENT_KINDS = ["charge", "payment", "refund", "gift", "credit"] as const;
export type MovementKind = (typeof MOVEMENT_KINDS)[number];

/** A filter chip; `all` shows every movement. */
export type MovementFilter = "all" | MovementKind;

/** Invoice states that still wait for money (the stored status; overdue is worked out on the server). */
export const OPEN_CHARGE_STATUSES = new Set(["issued", "partially_paid", "overdue"]);
const REVERSIBLE_PAYMENT_STATUSES = new Set(["paid", "waived"]);

export type ChargeMovement = {
  kind: "charge";
  id: string;
  /** `YYYY-MM-DD`, the day the list sorts by. */
  day: string;
  at: string;
  number: string;
  description: string;
  invoiceType: string;
  status: string;
  totalCents: number;
  paidCents: number;
  balanceCents: number;
  dueDate: string;
  /** Still waits for money: it gets its own «Πληρωμή». */
  open: boolean;
  voided: boolean;
  record: FinanceRecord;
};

export type PaymentMovement = {
  kind: "payment";
  id: string;
  day: string;
  at: string;
  amountCents: number;
  /** What can still be given back (net of earlier refunds). */
  refundableCents: number;
  method: string;
  status: string;
  notes: string;
  /** The charge it paid, when there is one. */
  chargeNumber: string;
  record: FinanceRecord;
};

export type RefundMovement = {
  kind: "refund";
  id: string;
  day: string;
  at: string;
  amountCents: number;
  reason: string;
  reversalType: string;
  record: FinanceRecord;
};

export type GiftMovement = {
  kind: "gift";
  id: string;
  day: string;
  at: string;
  benefit: MemberBenefit;
};

export type CreditMovement = {
  kind: "credit";
  id: string;
  day: string;
  at: string;
  amountCents: number;
  description: string;
  record: FinanceRecord;
};

export type Movement = ChargeMovement | PaymentMovement | RefundMovement | GiftMovement | CreditMovement;

export type MemberFinanceProfile = {
  invoices?: FinanceRecord[] | null;
  payments?: FinanceRecord[] | null;
  payment_reversals?: FinanceRecord[] | null;
  credit_ledger_entries?: FinanceRecord[] | null;
  package_subscriptions?: FinanceRecord[] | null;
  active_package_subscription?: FinanceRecord | null;
  credit_balance?: number | null;
};

function text(record: FinanceRecord | null | undefined, key: string): string {
  const value = record?.[key];
  return value === null || value === undefined ? "" : String(value);
}

function cents(record: FinanceRecord | null | undefined, key: string): number {
  const value = record?.[key];
  const number = typeof value === "number" ? value : Number(value ?? 0);
  return Number.isFinite(number) ? number : 0;
}

function dayOf(...values: string[]): string {
  return (values.find((value) => value) ?? "").slice(0, 10);
}

function chargeDescription(invoice: FinanceRecord): string {
  const lines = (invoice.lines as FinanceRecord[] | undefined) ?? [];
  const described = lines.map((line) => text(line, "description")).filter(Boolean);
  if (described.length) return described.join(" · ");
  return text(invoice, "notes");
}

export function chargeMovement(invoice: FinanceRecord): ChargeMovement {
  const status = text(invoice, "status");
  const balance = Math.max(cents(invoice, "balance_due_cents"), 0);
  const voided = status === "void" || Boolean(invoice.voided_at);
  return {
    kind: "charge",
    id: text(invoice, "id"),
    day: dayOf(text(invoice, "issue_date"), text(invoice, "due_date"), text(invoice, "inserted_at")),
    at: text(invoice, "inserted_at"),
    number: text(invoice, "invoice_number"),
    description: chargeDescription(invoice),
    invoiceType: text(invoice, "invoice_type"),
    status,
    totalCents: cents(invoice, "total_cents"),
    paidCents: cents(invoice, "paid_cents"),
    balanceCents: balance,
    dueDate: text(invoice, "due_date").slice(0, 10),
    open: !voided && OPEN_CHARGE_STATUSES.has(status) && balance > 0,
    voided,
    record: invoice,
  };
}

/** What can still be given back from a payment; nothing for one that is not settled. */
export function refundableCents(payment: FinanceRecord, reversals: FinanceRecord[] = []): number {
  if (!REVERSIBLE_PAYMENT_STATUSES.has(text(payment, "payment_status"))) return 0;
  const net = payment.net_amount_cents;
  if (typeof net === "number") return Math.max(net, 0);
  const id = text(payment, "id");
  const reversed = reversals
    .filter((reversal) => text(reversal, "membership_payment_id") === id)
    .reduce((sum, reversal) => sum + cents(reversal, "amount_cents"), 0);
  return Math.max(cents(payment, "amount_cents") - reversed, 0);
}

/**
 * Every movement, newest first. A forgiven debt is a gift (it carries who
 * and why), so its credit entry is not listed twice; credit applications and
 * offsets are bookkeeping and stay out of the list.
 */
export function movements(profile: MemberFinanceProfile | null | undefined, benefits: MemberBenefit[] = []): Movement[] {
  const invoices = profile?.invoices ?? [];
  const reversals = profile?.payment_reversals ?? [];
  const numbers = new Map(invoices.map((invoice) => [text(invoice, "id"), text(invoice, "invoice_number")]));

  const list: Movement[] = [
    ...invoices.map(chargeMovement),
    ...(profile?.payments ?? []).map<PaymentMovement>((payment) => ({
      kind: "payment",
      id: text(payment, "id"),
      day: dayOf(text(payment, "paid_on"), text(payment, "inserted_at")),
      at: text(payment, "inserted_at"),
      amountCents: cents(payment, "amount_cents"),
      refundableCents: refundableCents(payment, reversals),
      method: text(payment, "payment_method"),
      status: text(payment, "payment_status"),
      notes: text(payment, "notes"),
      chargeNumber: numbers.get(text(payment, "finance_invoice_id")) ?? "",
      record: payment,
    })),
    ...reversals.map<RefundMovement>((reversal) => ({
      kind: "refund",
      id: text(reversal, "id"),
      day: dayOf(text(reversal, "occurred_on"), text(reversal, "occurred_at"), text(reversal, "inserted_at")),
      at: text(reversal, "occurred_at") || text(reversal, "inserted_at"),
      amountCents: cents(reversal, "amount_cents"),
      reason: text(reversal, "reason"),
      reversalType: text(reversal, "reversal_type"),
      record: reversal,
    })),
    ...benefits.map<GiftMovement>((benefit) => ({
      kind: "gift",
      id: benefit.id,
      day: dayOf(benefit.given_at ?? ""),
      at: benefit.given_at ?? "",
      benefit,
    })),
    ...(profile?.credit_ledger_entries ?? [])
      .filter((entry) => text(entry, "entry_type") === "grant" && text(entry, "source_type") !== "forgiveness")
      .map<CreditMovement>((entry) => ({
        kind: "credit",
        id: text(entry, "id"),
        day: dayOf(text(entry, "occurred_on"), text(entry, "occurred_at"), text(entry, "inserted_at")),
        at: text(entry, "occurred_at") || text(entry, "inserted_at"),
        amountCents: cents(entry, "amount_cents"),
        description: text(entry, "description"),
        record: entry,
      })),
  ];

  return list.sort((a, b) => b.day.localeCompare(a.day) || b.at.localeCompare(a.at) || a.id.localeCompare(b.id));
}

/** What the person owes now: every open charge's balance. */
export function openDebtCents(profile: MemberFinanceProfile | null | undefined): number {
  return (profile?.invoices ?? []).map(chargeMovement).reduce((sum, charge) => sum + (charge.open ? charge.balanceCents : 0), 0);
}

/** The filters worth showing: «Όλες» and every kind the list holds, in a fixed order. */
export function availableFilters(list: Movement[]): MovementFilter[] {
  const kinds = new Set(list.map((movement) => movement.kind));
  return ["all", ...MOVEMENT_KINDS.filter((kind) => kinds.has(kind))];
}

export function filterMovements(list: Movement[], filter: MovementFilter): Movement[] {
  return filter === "all" ? list : list.filter((movement) => movement.kind === filter);
}

export type NextCharge = { day: string; amountCents: number; packageName: string };

/**
 * The next renewal charge: the day after the running period of a package
 * that renews, at its price. Nothing when it does not renew or is free.
 */
export function nextCharge(profile: MemberFinanceProfile | null | undefined): NextCharge | null {
  const subscription = profile?.active_package_subscription;
  if (!subscription || text(subscription, "status") !== "active") return null;
  const period = (subscription.current_period ?? null) as { ends_on?: string | null; renews?: boolean } | null;
  const endsOn = (period?.ends_on ?? text(subscription, "ends_on")).slice(0, 10);
  const amountCents = cents(subscription, "price_cents_snapshot");
  if (!period?.renews || !endsOn || amountCents <= 0) return null;
  const [year, month, day] = endsOn.split("-").map(Number);
  const next = new Date(Date.UTC(year, month - 1, day + 1)).toISOString().slice(0, 10);
  return {
    day: next,
    amountCents,
    packageName: text(subscription, "package_name") || text(subscription, "package_code_snapshot"),
  };
}

/** The package the person holds now (the one «Αλλαγή» and «Αφαίρεση» act on). */
export function heldSubscription(profile: MemberFinanceProfile | null | undefined): FinanceRecord | null {
  const active = profile?.active_package_subscription;
  if (active && text(active, "status") === "active") return active;
  return (profile?.package_subscriptions ?? []).find((subscription) => text(subscription, "status") === "active") ?? null;
}

/** Statuses of a package the person still holds (each can be removed on its own). */
const HELD_STATUSES = new Set(["active", "paused"]);

/** Every package the person holds now, active or paused, the current one first. */
export function heldSubscriptions(profile: MemberFinanceProfile | null | undefined): FinanceRecord[] {
  const current = heldSubscription(profile);
  const rest = (profile?.package_subscriptions ?? []).filter(
    (subscription) => HELD_STATUSES.has(text(subscription, "status")) && text(subscription, "id") !== text(current, "id"),
  );
  return current ? [current, ...rest] : rest;
}

/** What the person may do here, from the capabilities they already have (ANR pick 4). */
export type FinanceAbilities = {
  /** «+ Πληρωμή», a line's «Πληρωμή», «Δώρο ή χάρη». */
  takePayments: boolean;
  /** Refunds, «+ Χρέωση για κάτι νέο», voiding a charge. */
  manageBilling: boolean;
};

/** ANR pick 1 (C): the header shows the status and «+ Πληρωμή» only while something is owed, and never on the Finance tab itself. */
export function showsHeaderPayment({ owedCents, onFinanceTab, canTakePayments }: { owedCents: number; onFinanceTab: boolean; canTakePayments: boolean }) {
  return owedCents > 0 && !onFinanceTab && canTakePayments;
}
