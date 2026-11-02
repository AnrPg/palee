/**
 * The lists of Οικονομικά › Εκκρεμότητες and their addresses. Every alert that
 * counts something in one of them («1 συνδρομή λήγει…», «1 ληξιπρόθεσμο
 * τιμολόγιο», a staff notice) links here with the list already picked, so a
 * tap always lands on the rows it counted.
 */
export const FINANCE_QUEUES = ["debts", "awaiting", "expiring", "failed", "rewards", "promos"] as const;
export type FinanceQueue = (typeof FINANCE_QUEUES)[number];

/** Addresses written before the list ids settled (staff notices already sent). */
const QUEUE_ALIASES: Record<string, FinanceQueue> = {
  failed_charges: "failed",
  package_requests: "awaiting",
  overdue: "debts",
  overdue_invoices: "debts",
  open_charges: "debts",
  expiring_memberships: "expiring",
};

/** The list a `?queue=` value asks for, or null for the default. */
export function parseFinanceQueue(value: string | null | undefined): FinanceQueue | null {
  if (!value) return null;
  if ((FINANCE_QUEUES as readonly string[]).includes(value)) return value as FinanceQueue;
  return QUEUE_ALIASES[value] ?? null;
}

/** `/admin/finance?tab=queues&queue=<list>`: pass it through `adminHref`. */
export function financeQueueHref(queue: FinanceQueue): string {
  return `/admin/finance?${new URLSearchParams({ tab: "queues", queue }).toString()}`;
}
