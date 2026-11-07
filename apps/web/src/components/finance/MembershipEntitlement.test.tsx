import { fireEvent, render, screen, within } from "@testing-library/react";
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

const entitlement = (
  allowances: EffectiveEntitlement["allowances"],
  channels: string[] = ["facility", "in_person"],
): EffectiveEntitlement => ({
  status: "grace",
  enforcement_mode: "enforce",
  plan: { entitlement_version: 1, channels, capabilities: [] },
  allowances,
  usage_entries: [],
});

function renderCard(value: EffectiveEntitlement, { open = true } = {}) {
  const view = render(
    <NextIntlClientProvider locale="el" messages={el}>
      <EntitlementCard entitlement={value} />
    </NextIntlClientProvider>,
  );
  if (open) fireEvent.click(screen.getByRole("button", { name: new RegExp(el.Ui.yourPackageBenefitsb75c7f4) }));
  return view;
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
    renderCard(entitlement({ class_visits: usage(8, 5) }, ["in_person"]));
    const row = within(screen.getByTestId("entitlement-allowances")).getByRole("listitem");
    expect(row).toHaveTextContent("5");
    expect(row.querySelectorAll("p")).toHaveLength(3);
  });

  it("is closed until the member opens it (ANR 2026-11-07)", () => {
    renderCard(entitlement({ class_visits: usage(8, 5) }, ["in_person"]), { open: false });
    const toggle = screen.getByRole("button", { name: new RegExp(el.Ui.yourPackageBenefitsb75c7f4) });
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByRole("listitem")).toBeNull();
    fireEvent.click(toggle);
    expect(toggle).toHaveAttribute("aria-expanded", "true");
    expect(screen.getAllByRole("listitem")).toHaveLength(1);
  });

  it("tells each benefit once, as text: no chip repeats an allowance tile (ANR 2026-11-07)", () => {
    renderCard(entitlement({ class_visits: usage("unlimited", "unlimited"), open_gym_visits: usage("unlimited", "unlimited") }));
    expect(screen.queryByText(el.Ui.semanticInPerson)).toBeNull();
    expect(screen.queryByText(el.Ui.semanticFacility)).toBeNull();
    expect(within(screen.getByTestId("entitlement-allowances")).getAllByRole("listitem")).toHaveLength(2);
  });

  it("keeps a benefit without its own allowance as an «included» row", () => {
    renderCard(entitlement({ class_visits: usage(8, 5) }, ["in_person", "coach_messaging"]));
    const rows = within(screen.getByTestId("entitlement-allowances")).getAllByRole("listitem");
    expect(rows).toHaveLength(2);
    expect(rows[1]).toHaveTextContent(el.Ui.semanticCoachMessaging);
    expect(rows[1]).toHaveTextContent(el.Ui.pkgIncluded);
    expect(screen.queryByText(el.Ui.semanticInPerson)).toBeNull();
  });
});
