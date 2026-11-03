import { render, screen, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it } from "vitest";

import el from "../../../messages/el.json";

import type { AllowanceUsage, EffectiveEntitlement } from "@/api/my-finance";
import { EntitlementCard } from "./MembershipEntitlement";

const usage = (limit: AllowanceUsage["limit"], remaining: AllowanceUsage["remaining"]): AllowanceUsage => ({
  limit,
  remaining,
  period: "calendar_month",
  period_start: "2026-11-01",
  period_end: "2026-11-30",
  committed: 0,
  extensions: 0,
});

const entitlement = (allowances: EffectiveEntitlement["allowances"]): EffectiveEntitlement => ({
  status: "grace",
  enforcement_mode: "enforce",
  plan: { entitlement_version: 1, channels: ["open_gym", "in_person"], capabilities: [] },
  allowances,
  usage_entries: [],
});

function renderCard(value: EffectiveEntitlement) {
  return render(
    <NextIntlClientProvider locale="el" messages={el}>
      <EntitlementCard entitlement={value} />
    </NextIntlClientProvider>,
  );
}

describe("EntitlementCard", () => {
  it("says unlimited allowances in words, never the raw API token (ANR 2026-11-02)", () => {
    renderCard(entitlement({ class_visits: usage("unlimited", "unlimited"), open_gym_visits: usage("unlimited", "unlimited") }));
    const rows = within(screen.getByTestId("entitlement-allowances")).getAllByRole("listitem");
    expect(rows).toHaveLength(2);
    for (const row of rows) expect(row).toHaveTextContent(el.Ui.clUnlimited);
    expect(screen.queryByText(/unlimited/i)).toBeNull();
  });

  it("shows a counted allowance as a number with its quota line", () => {
    renderCard(entitlement({ class_visits: usage(8, 5) }));
    const row = within(screen.getByTestId("entitlement-allowances")).getByRole("listitem");
    expect(row).toHaveTextContent("5");
    expect(row.querySelectorAll("p")).toHaveLength(3);
  });
});
