import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../../../messages/el.json";

import { fetchConfirmationSkips, skipConfirmationToday } from "@/api/finance";

import { MoneyConfirmDialog, useMoneyConfirmation } from "./MoneyConfirm";

vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "tok" } }) }));
vi.mock("@/api/finance", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/finance")>()),
  fetchConfirmationSkips: vi.fn(),
  skipConfirmationToday: vi.fn(),
}));

function wrap(children: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        {children}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

function Asks() {
  const { ask } = useMoneyConfirmation("record_payment");
  return <p>{ask ? "ask" : "skip"}</p>;
}

describe("MoneyConfirm (ADR-795)", () => {
  beforeEach(() => {
    vi.mocked(fetchConfirmationSkips).mockResolvedValue({ day: "2026-11-28", skipped: [] });
    vi.mocked(skipConfirmationToday).mockResolvedValue({ day: "2026-11-28", skipped: ["record_payment"] });
  });

  it("asks «Έλαβες πραγματικά…;» and goes on only with «Ναι»", async () => {
    const onConfirm = vi.fn();
    const onBack = vi.fn();
    wrap(<MoneyConfirmDialog kind="record_payment" amount="45,00 €" onConfirm={onConfirm} onBack={onBack} />);
    expect(await screen.findByText("Έλαβες πραγματικά 45,00 €;")).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("money-confirm-back"));
    expect(onBack).toHaveBeenCalled();
    expect(onConfirm).not.toHaveBeenCalled();
    fireEvent.click(screen.getByTestId("money-confirm-yes"));
    await waitFor(() => expect(onConfirm).toHaveBeenCalled());
    expect(skipConfirmationToday).not.toHaveBeenCalled();
  });

  it("«Να μην εμφανιστεί ξανά σήμερα» is saved for the account before going on", async () => {
    const onConfirm = vi.fn();
    wrap(<MoneyConfirmDialog kind="desk_collect" amount="50,00 €" onConfirm={onConfirm} onBack={() => undefined} />);
    fireEvent.click(await screen.findByTestId("money-confirm-not-today"));
    fireEvent.click(screen.getByTestId("money-confirm-yes"));
    await waitFor(() => expect(onConfirm).toHaveBeenCalled());
    expect(skipConfirmationToday).toHaveBeenCalledWith("tok", "desk_collect");
  });

  it("offers the way out when no money changed hands", async () => {
    const onChoose = vi.fn();
    wrap(
      <MoneyConfirmDialog
        kind="record_payment"
        amount="50,00 €"
        wayOut={{ text: "Αν δεν πήρες χρήματα…", action: "Κλείσιμο χωρίς πληρωμή", onChoose }}
        onConfirm={() => undefined}
        onBack={() => undefined}
      />,
    );
    fireEvent.click(await screen.findByTestId("money-confirm-way-out"));
    expect(onChoose).toHaveBeenCalled();
  });

  it("skipped today: the question is not asked", async () => {
    vi.mocked(fetchConfirmationSkips).mockResolvedValue({ day: "2026-11-28", skipped: ["record_payment"] });
    wrap(<Asks />);
    expect(await screen.findByText("skip")).toBeInTheDocument();
  });
});
