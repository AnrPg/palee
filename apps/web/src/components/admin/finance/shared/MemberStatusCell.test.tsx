import { render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import el from "../../../../../messages/el.json";

import { MemberStatusCell } from "./MemberStandingCells";

vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "t" } }) }));
vi.mock("@/lib/membership-role", () => ({ useSelectedMembershipRole: () => ({ membership: null }) }));

function renderCell(props: Partial<React.ComponentProps<typeof MemberStatusCell>>) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <MemberStatusCell userId="u1" status="active" override={null} {...props} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("MemberStatusCell", () => {
  it("shows the server's one standing, never a stale status beside it", () => {
    renderCell({
      status: "active",
      standing: { status: "unpaid", grace_until: null, access_until: null, outstanding_cents: 5000, unpaid_since: "2026-11-20", benefit: null },
    });
    expect(screen.getByText("Απλήρωτο")).toHaveAttribute("data-member-status", "unpaid");
    expect(screen.queryByText("Ενεργό")).not.toBeInTheDocument();
    expect(screen.getByTestId("standing-line").textContent).toMatch(/50/);
  });

  it("keeps the plain status when no standing came", () => {
    renderCell({ status: "active" });
    expect(screen.getByText("Ενεργό")).toBeInTheDocument();
    expect(screen.queryByTestId("standing-line")).not.toBeInTheDocument();
  });
});
