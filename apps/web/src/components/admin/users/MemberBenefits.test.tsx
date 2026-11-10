import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../../messages/el.json";

import { fetchMemberBenefits, giveMemberBenefit, revokeMemberBenefit } from "@/api/member-benefits";

import { chooseOption } from "@/components/ui/select-test-utils";

import { MemberBenefits } from "./MemberBenefits";

vi.mock("@/api/member-benefits", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/member-benefits")>()),
  fetchMemberBenefits: vi.fn(),
  giveMemberBenefit: vi.fn(),
  revokeMemberBenefit: vi.fn(),
}));

const grace = {
  id: "b1",
  action: "grant",
  kind: "grace",
  state: "active",
  starts_on: "2026-11-10",
  ends_on: "2026-11-30",
  amount_cents: null,
  details: {},
  reason: "Δύσκολος μήνας",
  given_by_id: "a1",
  given_by_name: "Νίκος",
  given_by_roles: ["owner"],
  given_at: "2026-11-10T10:00:00Z",
  request_id: "r1",
  revocation: null,
};

function renderCard(canGive = true) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <MemberBenefits token="t" userId="u1" nickname="Μαρία" allowances={[{ key: "class_visits", label: "Επισκέψεις" }]} canGive={canGive} onRefresh={async () => undefined} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("MemberBenefits (ADR-612)", () => {
  beforeEach(() => {
    vi.mocked(fetchMemberBenefits).mockResolvedValue([grace] as never);
    vi.mocked(giveMemberBenefit).mockResolvedValue({ benefit: grace, replayed: false } as never);
    vi.mocked(revokeMemberBenefit).mockResolvedValue({ benefit: { ...grace, state: "revoked" }, replayed: false } as never);
  });

  it("shows who gave what, when and why", async () => {
    renderCard();
    expect(await screen.findByText(/Χάρη ως/)).toBeInTheDocument();
    expect(screen.getByText(/Από Νίκος/)).toBeInTheDocument();
    expect(screen.getByText("Λόγος: Δύσκολος μήνας")).toBeInTheDocument();
  });

  it("gives extra uses only after staff choose for how long", async () => {
    renderCard();
    fireEvent.click(await screen.findByTestId("member-benefit-open"));
    fireEvent.click(screen.getByTestId("member-benefit-kind-extra_uses"));
    chooseOption(screen.getByTestId("member-benefit-allowance"), "Επισκέψεις");
    expect(screen.getByTestId("member-benefit-submit")).toBeDisabled();
    fireEvent.click(screen.getByTestId("member-benefit-period-calendar_month"));
    fireEvent.click(screen.getByTestId("member-benefit-submit"));
    await waitFor(() =>
      expect(giveMemberBenefit).toHaveBeenCalledWith(
        "t",
        "u1",
        expect.objectContaining({ kind: "extra_uses", allowance: "class_visits", quantity: 1, period: "calendar_month", reason: null }),
      ),
    );
  });

  it("revokes a grace with an optional reason", async () => {
    renderCard();
    fireEvent.click(await screen.findByRole("button", { name: "Ανάκληση" }));
    fireEvent.click(screen.getByRole("button", { name: "Ανάκληση τώρα" }));
    await waitFor(() => expect(revokeMemberBenefit).toHaveBeenCalledWith("t", "u1", "b1", expect.objectContaining({ reason: null })));
  });

  it("only shows the history to staff who don't take payments", async () => {
    renderCard(false);
    expect(await screen.findByText(/Χάρη ως/)).toBeInTheDocument();
    expect(screen.queryByTestId("member-benefit-open")).toBeNull();
    expect(screen.queryByRole("button", { name: "Ανάκληση" })).toBeNull();
  });
});
