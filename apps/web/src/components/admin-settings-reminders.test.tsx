import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import el from "../../messages/el.json";

// ADR-500: the box's reminder schedule for a subscription that is not renewed.

const settings = vi.hoisted(() => ({
  fetchAdminSettings: vi.fn(async () => ({
    finance: {
      payment_reminder_interval_days: 7,
      subscription_expiry_reminder_days: 5,
      subscription_end_day_reminder: true,
      subscription_day_after_reminder: true,
      subscription_grace_days: 3,
      document_mode: "invoice",
      package_modules: ["group_classes", "online_coaching"],
    },
  })),
  updateAdminSettings: vi.fn(async (_token: string, body: unknown) => body),
}));

vi.mock("@/api/settings", async (original) => ({ ...(await original<object>()), ...settings }));
vi.mock("@/components/settings/AdvancedSettings", async (original) => ({
  ...(await original<object>()),
  useSettingLevels: () => ({ basic: () => false, advanced: () => true }),
}));
vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
  usePathname: () => "/admin/settings",
}));

import { FinanceSection } from "./admin-settings";

function renderSection() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <FinanceSection token="token" part="advanced" />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("FinanceSection reminder schedule", () => {
  it("shows the end-day and day-after reminders on by default and saves a change", async () => {
    renderSection();

    const endDay = await screen.findByLabelText("Υπενθύμιση την ημέρα της λήξης");
    const dayAfter = screen.getByLabelText("Υπενθύμιση την επόμενη μέρα μετά τη λήξη");
    await waitFor(() => expect(endDay).toBeChecked());
    expect(dayAfter).toBeChecked();
    expect(screen.getByText(/μέχρι να ανανεώσει ή να αποχωρήσει το μέλος/)).toBeInTheDocument();

    fireEvent.click(dayAfter);
    fireEvent.click(await screen.findByRole("button", { name: /Αποθήκευση/ }));

    await waitFor(() => expect(settings.updateAdminSettings).toHaveBeenCalled());
    const [, body] = settings.updateAdminSettings.mock.calls[0] as unknown as [string, { finance: Record<string, unknown> }];
    expect(body.finance).toMatchObject({
      subscription_end_day_reminder: true,
      subscription_day_after_reminder: false,
    });
  });
});
