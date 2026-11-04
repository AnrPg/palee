import { featureOn, showsWork, type BusinessFeatureState } from "@/lib/business-features";

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

/**
 * The lists offered as chips, in order. ADR-470: a list tied to a feature
 * the business has not switched on is left out (failed charges need saved
 * card payments, rewards a referral programme, promo uses a running
 * promotion), unless rows are still waiting in it: owed is still owed.
 * Desk payment requests (ADR-291) exist only while packages are not sold
 * online. Until the feature answer arrives, feature lists stay hidden.
 */
export function offeredQueues(input: {
  seesFailed: boolean;
  seesAwaiting: boolean;
  counts: Record<FinanceQueue, number>;
  features: BusinessFeatureState;
}): FinanceQueue[] {
  const { seesFailed, seesAwaiting, counts, features } = input;
  const sellsPackagesOnline = features.status === "loading" || featureOn(features, "online_packages");
  const offered: Record<FinanceQueue, boolean> = {
    debts: true,
    awaiting: seesAwaiting && (!sellsPackagesOnline || counts.awaiting > 0),
    expiring: true,
    failed: seesFailed && showsWork(features, "card_autopay", counts.failed),
    rewards: showsWork(features, "referrals", counts.rewards),
    promos: showsWork(features, "promotions", counts.promos),
  };
  return FINANCE_QUEUES.filter((queue) => offered[queue]);
}
