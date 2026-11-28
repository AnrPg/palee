import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";
import type { ActivityLogPage } from "@/api/activity-log";

import { entry } from "./activity-log-test-utils";

const api = vi.hoisted(() => ({
  fetchActivityLog: vi.fn(),
  exportActivityLog: vi.fn(),
  fetchMyActivity: vi.fn(),
  saveFile: vi.fn(),
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" } }),
}));
vi.mock("@/lib/organization-slug", () => ({
  useOrganizationSlug: () => "box",
  useOrganizationTimeZone: () => "Europe/Athens",
  adminHref: (href: string) => href,
}));
vi.mock("@/api/activity-log", async (original) => ({
  ...(await original<object>()),
  fetchActivityLog: api.fetchActivityLog,
  exportActivityLog: api.exportActivityLog,
  fetchMyActivity: api.fetchMyActivity,
}));
vi.mock("@/api/staff", () => ({ fetchGymStaff: vi.fn().mockResolvedValue([]) }));
vi.mock("@/api/admin-users", () => ({ fetchAdminUsers: vi.fn().mockResolvedValue({ users: [] }) }));
vi.mock("@/components/admin/coach-pay/pay-ui", () => ({ saveFile: api.saveFile }));

import { ActivityLogList } from "./ActivityLogList";
import { MemberActivityHistory } from "./MemberActivityHistory";

function page(overrides: Partial<ActivityLogPage> = {}): ActivityLogPage {
  return { entries: [], next_cursor: null, can_export: false, areas: ["members", "packages"], ...overrides };
}

function wrap(ui: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="UTC">
        {ui}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("ActivityLogList (ADR-760)", () => {
  beforeEach(() => {
    api.fetchActivityLog.mockReset();
    api.exportActivityLog.mockReset();
    api.fetchMyActivity.mockReset();
    api.saveFile.mockReset();
  });

  it("groups rows by day and opens a row's details", async () => {
    api.fetchActivityLog.mockResolvedValue(
      page({
        entries: [
          entry({
            id: "a",
            occurred_at: "2026-11-23T11:20:00Z",
            action: "member.status_set",
            area: "members",
            reason: "Paid cash",
            reason_shared: true,
            details: { changes: [{ field: "status", before: "overdue", after: "active" }] },
          }),
          entry({ id: "b", occurred_at: "2026-11-20T09:00:00Z", action: "package.assign", subject_label: "Monthly" }),
        ],
      }),
    );
    wrap(<ActivityLogList />);

    const rows = await screen.findAllByTestId("activity-log-entry");
    expect(rows).toHaveLength(2);
    expect(within(rows[0]).getByText(en.ActivityLog.actions.member.status_set, { exact: false })).toBeTruthy();
    expect(within(rows[0]).getByText(en.ActivityLog.areas.members)).toBeTruthy();
    expect(within(rows[1]).getByText(/Maria K\. · Monthly/)).toBeTruthy();
    // Athens time: 11:20 UTC is 13:20 there.
    expect(within(rows[0]).getByText(/0?1:20/)).toBeTruthy();

    fireEvent.click(within(rows[0]).getByRole("button", { expanded: false }));
    const detail = await screen.findByTestId("activity-log-detail");
    expect(within(detail).getByText("Paid cash")).toBeTruthy();
    expect(within(detail).getByText(en.ActivityLog.memberSaw)).toBeTruthy();
    expect(within(detail).getByText(en.ActivityLog.yes)).toBeTruthy();
    expect(within(detail).getByText(en.MemberStanding.status_active)).toBeTruthy();
  });

  it("shows a deleted account as «Deleted member» without a reason", async () => {
    api.fetchActivityLog.mockResolvedValue(
      page({ entries: [entry({ redacted: true, person: { id: "p", name: null }, reason: "private" })] }),
    );
    wrap(<ActivityLogList />);
    const row = await screen.findByTestId("activity-log-entry");
    expect(within(row).getByText(en.ActivityLog.deletedMember)).toBeTruthy();
    expect(screen.queryByText(/private/)).toBeNull();
    fireEvent.click(within(row).getByRole("button", { expanded: false }));
    expect(await screen.findByText(en.ActivityLog.noReason)).toBeTruthy();
  });

  it("offers CSV only when the page allows it, with the same filters", async () => {
    api.fetchActivityLog.mockResolvedValueOnce(page());
    const first = wrap(<ActivityLogList />);
    await waitFor(() => expect(api.fetchActivityLog).toHaveBeenCalled());
    expect(screen.queryByTestId("activity-log-export")).toBeNull();
    first.unmount();

    api.fetchActivityLog.mockResolvedValue(page({ can_export: true }));
    api.exportActivityLog.mockResolvedValue(new Blob(["csv"]));
    wrap(<ActivityLogList personId="p9" />);
    fireEvent.click(await screen.findByTestId("activity-log-export"));
    await waitFor(() => expect(api.saveFile).toHaveBeenCalled());
    expect(api.exportActivityLog).toHaveBeenCalledWith("token", expect.objectContaining({ person_id: "p9" }));
  });

  it("filters by the reader's areas only and pages on with the cursor", async () => {
    api.fetchActivityLog.mockImplementation((_token: string, _filters: unknown, cursor: string | null) =>
      Promise.resolve(
        cursor
          ? page({ entries: [entry({ id: "older", occurred_at: "2026-11-01T10:00:00Z" })] })
          : page({ entries: [entry({ id: "newer" })], next_cursor: "c1" }),
      ),
    );
    wrap(<ActivityLogList />);
    fireEvent.click(await screen.findByTestId("activity-log-more"));
    await waitFor(() => expect(screen.getAllByTestId("activity-log-entry")).toHaveLength(2));
    expect(api.fetchActivityLog).toHaveBeenLastCalledWith("token", expect.anything(), "c1", expect.anything());

    fireEvent.click(screen.getByRole("button", { expanded: false, name: /Filters/ }));
    const kinds = screen.getByRole("group", { name: en.ActivityLog.area });
    expect(within(kinds).getAllByRole("button").map((button) => button.textContent)).toEqual([
      en.ActivityLog.areas.members,
      en.ActivityLog.areas.packages,
    ]);
    fireEvent.click(within(kinds).getByText(en.ActivityLog.areas.packages));
    await waitFor(() =>
      expect(api.fetchActivityLog).toHaveBeenLastCalledWith("token", expect.objectContaining({ areas: ["packages"] }), null, expect.anything()),
    );
  });

  it("fixed to one person, it has no filter bar and asks for that person", async () => {
    api.fetchActivityLog.mockResolvedValue(page());
    wrap(<ActivityLogList personId="p1" fullLogHref="/admin/activity-log?person=p1" />);
    await waitFor(() => expect(api.fetchActivityLog).toHaveBeenCalledWith("token", expect.objectContaining({ person_id: "p1" }), null, expect.anything()));
    expect(screen.queryByRole("search")).toBeNull();
    expect(screen.getByTestId("activity-log-full").getAttribute("href")).toBe("/admin/activity-log?person=p1");
  });
});

describe("MemberActivityHistory (5A)", () => {
  beforeEach(() => api.fetchMyActivity.mockReset());

  it("names the box, never the staff member, and stays hidden when empty", async () => {
    api.fetchMyActivity.mockResolvedValue({
      entries: [
        {
          id: "m1",
          occurred_at: "2026-11-22T10:00:00Z",
          action: "package.remove",
          area: "packages",
          person: { id: "me", name: "Anna" },
          subject: {},
          subject_label: "10 visits",
          details: {},
          reason: "Moved to another city",
          redacted: false,
        },
      ],
      next_cursor: null,
    });
    wrap(<MemberActivityHistory slug="box" />);
    const row = await screen.findByTestId("member-activity-entry");
    expect(within(row).getByText(new RegExp(en.ActivityLog.theBox))).toBeTruthy();
    expect(within(row).getByText(/Removed a subscription package «10 visits»/)).toBeTruthy();
    expect(within(row).getByText("Reason: Moved to another city")).toBeTruthy();
    expect(screen.queryByText(/Eleni/)).toBeNull();
    expect(api.fetchMyActivity).toHaveBeenCalledWith("token", "box", null);
  });

  it("shows nothing without shared rows", async () => {
    api.fetchMyActivity.mockResolvedValue({ entries: [], next_cursor: null });
    wrap(<MemberActivityHistory slug="box" />);
    await waitFor(() => expect(api.fetchMyActivity).toHaveBeenCalled());
    expect(screen.queryByTestId("member-activity")).toBeNull();
  });
});
