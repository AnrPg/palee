import { describe, expect, test } from "vitest";

import { FINANCE_QUEUES, financeQueueHref, offeredQueues, parseFinanceQueue } from "./finance-queues";

describe("finance queue addresses", () => {
  test("every list has an address that reads back as the same list", () => {
    for (const queue of FINANCE_QUEUES) {
      const url = new URL(financeQueueHref(queue), "http://localhost");
      expect(url.pathname).toBe("/admin/finance");
      expect(url.searchParams.get("tab")).toBe("queues");
      expect(parseFinanceQueue(url.searchParams.get("queue"))).toBe(queue);
    }
  });

  test("addresses already sent in staff notices still open their list", () => {
    expect(parseFinanceQueue("failed_charges")).toBe("failed");
    expect(parseFinanceQueue("package_requests")).toBe("awaiting");
    expect(parseFinanceQueue("overdue_invoices")).toBe("debts");
  });

  test("an unknown or missing list falls back to the default", () => {
    expect(parseFinanceQueue(null)).toBeNull();
    expect(parseFinanceQueue("")).toBeNull();
    expect(parseFinanceQueue("nope")).toBeNull();
  });
});

describe("lists offered for this business (ADR-470)", () => {
  const none = { debts: 0, awaiting: 0, expiring: 0, failed: 0, rewards: 0, promos: 0 };
  const off = { status: "ready" as const, features: { online_packages: false, card_autopay: false, referrals: false, promotions: false } };

  test("a box without online payments, referrals or promotions sees only what applies to it", () => {
    expect(offeredQueues({ seesFailed: true, seesAwaiting: true, counts: none, features: off })).toEqual(["debts", "awaiting", "expiring"]);
  });

  test("switched-on features bring their lists; packages sold online drop the desk requests", () => {
    const on = { status: "ready" as const, features: { online_packages: true, card_autopay: true, referrals: true, promotions: true } };
    expect(offeredQueues({ seesFailed: true, seesAwaiting: true, counts: none, features: on })).toEqual([
      "debts",
      "expiring",
      "failed",
      "rewards",
      "promos",
    ]);
    expect(offeredQueues({ seesFailed: false, seesAwaiting: false, counts: none, features: on })).toEqual(["debts", "expiring", "rewards", "promos"]);
  });

  test("a list with rows still waiting stays after its feature is turned off", () => {
    const counts = { ...none, failed: 1, rewards: 2 };
    expect(offeredQueues({ seesFailed: true, seesAwaiting: false, counts, features: off })).toEqual(["debts", "expiring", "failed", "rewards"]);
  });

  test("feature lists stay hidden until the answer arrives, and show if it cannot be read", () => {
    expect(offeredQueues({ seesFailed: true, seesAwaiting: true, counts: none, features: { status: "loading" } })).toEqual(["debts", "expiring"]);
    expect(offeredQueues({ seesFailed: true, seesAwaiting: true, counts: none, features: { status: "error" } })).toEqual([
      "debts",
      "expiring",
      "failed",
      "rewards",
      "promos",
    ]);
  });
});
