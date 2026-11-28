import { expect, type Page } from "./test";

/** ADR-784: dates, freezes, gifts and leaving sit under «Περισσότερα» in a member's finance tab. */
export async function openFinanceMore(page: Page) {
  const more = page.getByTestId("member-finance-more");
  const summary = more.locator("summary");
  await expect(summary).toBeVisible();
  if ((await more.getAttribute("open")) === null) await summary.click();
  await expect(more).toHaveAttribute("open", "");
}

/**
 * ADR-795: «Έλαβες πραγματικά τα χρήματα;» comes before money is written down
 * (until «Να μην εμφανιστεί ξανά σήμερα»). Answers «Ναι» and checks the question named the amount.
 */
export async function confirmMoney(page: Page, amount: string | RegExp) {
  const yes = page.getByTestId("money-confirm-yes");
  await expect(yes).toBeVisible();
  await expect(yes).toBeEnabled();
  await expect(page.getByRole("dialog").filter({ has: yes })).toContainText(amount);
  await yes.click();
}
