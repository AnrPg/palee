import { fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";

import en from "../../../../../messages/en.json";
import type { PackageTermsPreview } from "@/api/finance";
import { termValue } from "@/components/finance/package-terms";
import type { UiTranslator } from "@/i18n/presentation";

import { PackageTermsApplySheet } from "./PackageTermsApplySheet";

// ADR-770 (1A): «Ισχύει και για τα ενεργά μέλη;» after «Αποθήκευση αλλαγών».

function preview(overrides: Partial<PackageTermsPreview> = {}): PackageTermsPreview {
  return {
    holders_count: 2,
    needs_choice: true,
    earliest_next_on: "2026-12-05",
    changes: [
      { key: "booking.window_days", from: 7, to: 14, timing: "now", direction: "better" },
      { key: "price", from: 6000, to: 6500, timing: "next_period", direction: "worse" },
    ],
    holders: [
      { subscription_id: "s1", membership_id: "m1", user_id: "u1", nickname: "Eleni", next_period_on: "2026-12-05", now_count: 1, next_count: 1, notes: [] },
      { subscription_id: "s2", membership_id: "m2", user_id: "u2", nickname: "Maria", next_period_on: null, now_count: 1, next_count: 0, notes: ["renewal_stopped"] },
    ],
    ...overrides,
  };
}

function wrap(ui: ReactNode) {
  return render(
    <NextIntlClientProvider locale="en" messages={en}>
      {ui}
    </NextIntlClientProvider>,
  );
}

describe("PackageTermsApplySheet", () => {
  it("chooses nothing in advance and saves only after a pick", () => {
    const onConfirm = vi.fn();
    wrap(<PackageTermsApplySheet preview={preview()} saving={false} onCancel={() => {}} onConfirm={onConfirm} />);

    expect(screen.getByText("Apply to the 2 active members too?")).toBeTruthy();
    const save = screen.getByTestId("package-terms-save") as HTMLButtonElement;
    expect(save.disabled).toBe(true);
    expect(screen.getByText("Now")).toBeTruthy();
    expect(screen.getByText("Next period")).toBeTruthy();

    fireEvent.click(screen.getByTestId("package-terms-new-only"));
    expect(save.disabled).toBe(false);
    fireEvent.click(save);
    expect(onConfirm).toHaveBeenCalledWith({ apply_to: "new_only", excluded_subscription_ids: [] });
  });

  it("leaves out the members staff untick (ε)", () => {
    const onConfirm = vi.fn();
    wrap(<PackageTermsApplySheet preview={preview()} saving={false} onCancel={() => {}} onConfirm={onConfirm} />);

    fireEvent.click(screen.getByTestId("package-terms-active"));
    fireEvent.click(screen.getByText("Who are the 2 members"));
    expect(screen.getByText("stopped renewing")).toBeTruthy();
    fireEvent.click(screen.getByLabelText("Maria"));
    fireEvent.click(screen.getByTestId("package-terms-save"));
    expect(onConfirm).toHaveBeenCalledWith({ apply_to: "active", excluded_subscription_ids: ["s2"] });
  });
});

describe("termValue", () => {
  const t = ((key: string, values?: Record<string, unknown>) => `${key}${values ? JSON.stringify(values) : ""}`) as unknown as UiTranslator;

  it("reads quotas, durations, lists and the price", () => {
    expect(termValue(t, "en", "group_classes.visits", { limit: 8, period: "calendar_month" })).toBe("8 pkgPeriod_calendar_month");
    expect(termValue(t, "en", "group_classes.visits", { limit: "unlimited", period: "calendar_month" })).toBe("pkgUnlimited");
    expect(termValue(t, "en", "terms.validity", { amount: 2, unit: "month" })).toBe('pkgDuration_month{"count":2}');
    expect(termValue(t, "en", "group_classes.class_types", ["a", "b"], new Map([["a", "WOD"], ["b", "Yoga"]]))).toBe("WOD, Yoga");
    expect(termValue(t, "en", "group_classes.class_types", ["a"])).toBe('pkgTermsCount{"count":1}');
    expect(termValue(t, "en", "booking.daily_limit", null)).toBe("pkgNoLimit");
    expect(termValue(t, "en", "price", 6500)).toBe("€65.00");
  });
});
