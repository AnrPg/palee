import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../../messages/el.json";

import { decideJoinRequest, fetchStaffJoinRequests } from "@/api/join-requests";

import { JoinRequestsCard } from "./JoinRequestsCard";

vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "access" } }) }));
vi.mock("@/api/join-requests", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/join-requests")>()),
  fetchStaffJoinRequests: vi.fn(),
  decideJoinRequest: vi.fn(),
}));

const row = {
  id: "r1",
  status: "requested",
  requested_at: "2026-11-07T10:00:00Z",
  decided_at: null,
  person: { id: "u1", nickname: "Μαρία", handle: "maria", avatar_url: null },
};

function renderCard(onAccepted = vi.fn()) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <JoinRequestsCard onAccepted={onAccepted} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
  return onAccepted;
}

describe("JoinRequestsCard (ADR-552)", () => {
  beforeEach(() => {
    vi.mocked(decideJoinRequest).mockResolvedValue({ request: { ...row, status: "accepted" } } as never);
  });

  it("is not shown while nobody waits", async () => {
    vi.mocked(fetchStaffJoinRequests).mockResolvedValue({ requests: [] });
    renderCard();
    await waitFor(() => expect(fetchStaffJoinRequests).toHaveBeenCalled());
    expect(screen.queryByTestId("join-requests")).toBeNull();
  });

  it("lists who asks and accepts them", async () => {
    vi.mocked(fetchStaffJoinRequests).mockResolvedValue({ requests: [row] } as never);
    const onAccepted = renderCard();
    expect(await screen.findByText("1 άτομο ζητά να γίνει μέλος")).toBeInTheDocument();
    expect(screen.getByText(/@maria/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Αποδοχή του/της Μαρία ως μέλος box" }));
    await waitFor(() => expect(decideJoinRequest).toHaveBeenCalledWith("access", "r1", "accept"));
    await waitFor(() => expect(onAccepted).toHaveBeenCalled());
  });
});
