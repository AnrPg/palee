import { fireEvent, render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

import { askToJoin, cancelJoinRequest, fetchMyJoinRequest } from "@/api/join-requests";
import type { PublicBoxPage } from "@/api/social";

import { JoinBoxAction } from "./JoinBoxAction";

vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "access" } }) }));
const push = vi.fn();
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));
// The packages this person sees: none known, so the page's own answer decides.
vi.mock("@/components/payments/BoxSales", () => ({ useBoxSales: () => ({ shownCount: null, isLoading: false }) }));
vi.mock("@/api/join-requests", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/join-requests")>()),
  fetchMyJoinRequest: vi.fn(),
  askToJoin: vi.fn(),
  cancelJoinRequest: vi.fn(),
}));

const box = { organization_id: "org-1", slug: "kypseli", name: "Box Κυψέλη", logo_url: null, primary_color: null };
const page = (joining: { packages: boolean; join_link: boolean }) => ({ box, joining }) as unknown as PublicBoxPage;
const request = (status: string) => ({ id: "r1", status, requested_at: "2026-11-07T10:00:00Z", decided_at: null, box: { slug: "kypseli", name: "Box Κυψέλη" } });

function renderAction(joining: { packages: boolean; join_link: boolean }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <JoinBoxAction page={page(joining)} signedIn />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("JoinBoxAction (ADR-552)", () => {
  beforeEach(() => {
    push.mockReset();
    window.history.replaceState(null, "", "/b/kypseli");
    vi.mocked(fetchMyJoinRequest).mockResolvedValue({ request: null });
    vi.mocked(askToJoin).mockResolvedValue({ request: request("requested") } as never);
    vi.mocked(cancelJoinRequest).mockResolvedValue({ request: request("cancelled") } as never);
  });

  it("links to the packages when the box lists any", () => {
    renderAction({ packages: true, join_link: false });
    expect(screen.getByTestId("box-page-join")).toHaveAttribute("href", "/b/kypseli/packages");
  });

  it("without packages or a join link, asks the box and shows that it waits", async () => {
    renderAction({ packages: false, join_link: false });
    const button = screen.getByTestId("box-page-join");
    expect(button).toHaveTextContent("Γίνε μέλος box");
    fireEvent.click(button);
    fireEvent.click(await screen.findByTestId("box-join-send"));
    expect(await screen.findByTestId("box-join-pending")).toHaveTextContent("Περιμένει έγκριση από το box");
    expect(askToJoin).toHaveBeenCalledWith("access", "kypseli");
    expect(screen.getAllByText("Περιμένει έγκριση από το box").length).toBeGreaterThan(1);
  });

  it("a waiting request can be withdrawn", async () => {
    vi.mocked(fetchMyJoinRequest).mockResolvedValue({ request: request("requested") } as never);
    renderAction({ packages: false, join_link: false });
    fireEvent.click(await screen.findByText("Περιμένει έγκριση από το box"));
    fireEvent.click(await screen.findByText("Ακύρωση αιτήματος"));
    expect(await screen.findByTestId("box-join-send")).toBeInTheDocument();
    expect(cancelJoinRequest).toHaveBeenCalledWith("access", "kypseli");
  });

  it("ADR-638: opened with ?join=1, goes on to the way in and drops the flag", () => {
    window.history.replaceState(null, "", "/b/kypseli?join=1");
    renderAction({ packages: true, join_link: false });
    expect(push).toHaveBeenCalledWith("/b/kypseli/packages");
    expect(window.location.search).toBe("");
  });

  it("ADR-638: opened with ?join=1 and no other way in, opens the ask sheet", async () => {
    window.history.replaceState(null, "", "/b/kypseli?join=1");
    renderAction({ packages: false, join_link: false });
    expect(await screen.findByTestId("box-join-send")).toBeInTheDocument();
    expect(push).not.toHaveBeenCalled();
  });
});
