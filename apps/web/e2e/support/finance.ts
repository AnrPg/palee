import { expect, type Page } from "./test";

/** ADR-784: dates, freezes, gifts and leaving sit under «Περισσότερα» in a member's finance tab. */
export async function openFinanceMore(page: Page) {
  const more = page.getByTestId("member-finance-more");
  const summary = more.locator("summary");
  await expect(summary).toBeVisible();
  if ((await more.getAttribute("open")) === null) await summary.click();
  await expect(more).toHaveAttribute("open", "");
}
