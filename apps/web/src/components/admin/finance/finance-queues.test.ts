import { describe, expect, test } from "vitest";

import { FINANCE_QUEUES, financeQueueHref, parseFinanceQueue } from "./finance-queues";

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
