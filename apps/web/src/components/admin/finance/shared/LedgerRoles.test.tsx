import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../../../messages/el.json";

import { changeClientRoles, previewClientRoles } from "@/api/roles";
import { BulkRolesDialog, RolesCell } from "./LedgerRoles";
import { memberRoles, roleRank } from "./ledger-roles";

const state = vi.hoisted(() => ({ actorRoles: ["owner"] as string[], grant: true }));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, currentUser: { id: "me" }, status: "authenticated" }),
}));
vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({
    membership: {
      role: state.actorRoles[0],
      roles: state.actorRoles,
      capabilities: state.grant ? { grant_staff_roles: "all" } : {},
    },
  }),
}));
vi.mock("@/api/roles", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/roles")>()),
  previewClientRoles: vi.fn(),
  changeClientRoles: vi.fn(),
}));

function wrap(node: React.ReactNode) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="el" messages={el} timeZone="Europe/Athens">
        {node}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const nikos = { id: "u1", nickname: "Νίκος", roles: ["coach", "member"], identity_role: "member" };

beforeEach(() => {
  state.actorRoles = ["owner"];
  state.grant = true;
  vi.mocked(previewClientRoles).mockReset();
  vi.mocked(changeClientRoles).mockReset();
});

describe("ledger roles (ADR-812)", () => {
  it("lists every role, client roles first, and sorts by the first", () => {
    expect(memberRoles(nikos)).toEqual(["member", "coach"]);
    expect(memberRoles({ identity_role: "athlete" })).toEqual(["athlete"]);
    expect(roleRank({ roles: ["athlete"] })).toBeGreaterThan(roleRank({ roles: ["member"] }));
  });

  it("shows the roles as chips only to someone without the right to change roles", () => {
    state.actorRoles = ["accountant"];
    state.grant = false;
    wrap(<RolesCell member={nikos} />);
    const chips = screen.getByTestId("ledger-role-chips");
    expect(within(chips).getByText("Μέλος box")).toBeTruthy();
    expect(screen.queryByTestId("ledger-roles-button")).toBeNull();
  });

  it("warns about cancelled bookings and the kept package, then saves the difference", async () => {
    vi.mocked(previewClientRoles).mockResolvedValue([
      { user_id: "u1", status: "preview", roles: ["guest", "coach"], impact: { future_bookings: 3, kept_package: { name: "12 επισκέψεις", ends_on: "2026-12-12" } } },
    ]);
    vi.mocked(changeClientRoles).mockResolvedValue([{ user_id: "u1", status: "changed", roles: ["coach", "guest"] }]);
    wrap(<RolesCell member={nikos} />);

    fireEvent.click(screen.getByTestId("ledger-roles-button"));
    const options = screen.getByTestId("ledger-roles-options");
    fireEvent.click(within(options).getByRole("button", { name: /Μέλος box/ }));
    // δ: without a client role nothing can be saved.
    expect(screen.getByText(/Κράτα τουλάχιστον έναν ρόλο πελάτη/)).toBeTruthy();
    expect((screen.getByTestId("ledger-roles-save") as HTMLButtonElement).disabled).toBe(true);

    fireEvent.click(within(options).getByRole("button", { name: /Επισκέπτης/ }));
    const impact = await screen.findByTestId("ledger-roles-impact");
    expect(impact.textContent).toContain("Θα ακυρωθούν 3 μελλοντικές κρατήσεις.");
    expect(impact.textContent).toMatch(/«12 επισκέψεις» μένει ενεργό μέχρι .*12/);
    expect(impact.textContent).not.toContain("2026-12-12");

    await waitFor(() => expect((screen.getByTestId("ledger-roles-save") as HTMLButtonElement).disabled).toBe(false));
    fireEvent.click(screen.getByTestId("ledger-roles-save"));
    await waitFor(() =>
      expect(changeClientRoles).toHaveBeenCalledWith("access", { user_ids: ["u1"], add: ["guest"], remove: ["member"] }),
    );
  });

  it("applies one change to many and names who was refused", async () => {
    vi.mocked(previewClientRoles).mockResolvedValue([
      { user_id: "u1", status: "preview", roles: ["member", "athlete"], impact: { future_bookings: 0, kept_package: null } },
      { user_id: "u2", status: "unchanged", roles: ["athlete"] },
    ]);
    vi.mocked(changeClientRoles).mockResolvedValue([
      { user_id: "u1", status: "changed", roles: ["member", "athlete"] },
      { user_id: "u2", status: "refused", roles: ["athlete"], code: "client_role_required" },
    ]);
    const onDone = vi.fn();
    wrap(
      <BulkRolesDialog
        members={[nikos, { id: "u2", nickname: "Ελένη", roles: ["athlete"] }]}
        onClose={() => {}}
        onDone={onDone}
      />,
    );

    fireEvent.click(screen.getAllByRole("radio").find((radio) => radio.dataset.role === "athlete" && radio.dataset.choice === "add")!);
    await screen.findByText("Θα αλλάξει 1 πελάτης.");
    fireEvent.click(screen.getByTestId("ledger-bulk-apply"));

    expect(await screen.findByTestId("ledger-bulk-done")).toBeTruthy();
    expect(changeClientRoles).toHaveBeenCalledWith("access", { user_ids: ["u1", "u2"], add: ["athlete"], remove: [] });
    expect(screen.getByTestId("ledger-bulk-refused").textContent).toContain("Ελένη");
  });
});
