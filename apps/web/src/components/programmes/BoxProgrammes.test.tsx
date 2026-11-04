import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

const api = vi.hoisted(() => ({ fetchBoxProgrammes: vi.fn() }));
vi.mock("@/api/programmes", async (original) => ({ ...(await original<object>()), ...api }));

import { BoxProgrammes } from "./BoxProgrammes";

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <BoxProgrammes slug="akropoli" />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

// «Όλα τα προγράμματα (N)» from the box website (ADR-543).
describe("BoxProgrammes", () => {
  beforeEach(() => api.fetchBoxProgrammes.mockReset());

  it("lists every programme of the box as a card linking to its page", async () => {
    api.fetchBoxProgrammes.mockResolvedValue({
      box: { name: "CrossFit Ακρόπολη" },
      programmes: [{ id: "p1", title: "Δύναμη σε 6 εβδομάδες", weeks: 6, price_cents: 3900, currency: "EUR" }, { title: "χωρίς id" }],
    });
    wrap();
    const card = await screen.findByTestId("box-programme-p1");
    expect(within(card).getByRole("link", { name: "Δες το" }).getAttribute("href")).toBe("/b/akropoli/programmes/p1");
    expect(screen.getByRole("link", { name: /CrossFit Ακρόπολη/ }).getAttribute("href")).toBe("/b/akropoli");
    expect(screen.getAllByRole("article")).toHaveLength(1);
  });

  it("says the box sells none for a stub that answers {}", async () => {
    api.fetchBoxProgrammes.mockResolvedValue({});
    wrap();
    expect(await screen.findByText("Αυτό το box δεν έχει ακόμη προγράμματα προπόνησης σε πώληση.")).toBeTruthy();
  });
});
