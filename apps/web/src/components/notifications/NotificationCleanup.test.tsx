import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { NotificationRecord } from "@/api/notifications";

const api = vi.hoisted(() => ({
  fetchNotifications: vi.fn(),
  deleteNotifications: vi.fn(),
}));

vi.mock("@/api/notifications", () => api);

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) => (values ? `${key}:${JSON.stringify(values)}` : key),
  useLocale: () => "en",
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "token" }, currentUser: { id: "u1", role: "member" } }),
}));

import { NotificationCleanup, OLD_AFTER_DAYS, cleanupFilter } from "./NotificationCleanup";

function notification(id: string, overrides: Partial<NotificationRecord> = {}): NotificationRecord {
  return {
    id,
    user_id: "u1",
    organization_id: null,
    type: "booking_approved",
    payload: {},
    read_at: "2026-10-01T10:00:00Z",
    inserted_at: "2026-10-01T09:00:00Z",
    ...overrides,
  };
}

function renderCleanup() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NotificationCleanup categories={["bookings", "messages"]} />
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  api.fetchNotifications.mockReset();
  api.deleteNotifications.mockReset();
  api.fetchNotifications.mockResolvedValue({
    notifications: [notification("a"), notification("b")],
    unread_count: 0,
    next_cursor: "next",
    matching_count: 42,
  });
});

describe("cleanupFilter (ADR-460)", () => {
  it("maps the chips to the server's filter", () => {
    expect(cleanupFilter("all", null)).toEqual({});
    expect(cleanupFilter("read", "bookings")).toEqual({ state: "read", category: "bookings" });
    expect(cleanupFilter("old", null)).toEqual({ older_than_days: OLD_AFTER_DAYS });
  });
});

describe("NotificationCleanup («Διαγραφή ειδοποιήσεων», ADR-460)", () => {
  it("loads a page with the matching count and refetches with the chosen filter", async () => {
    renderCleanup();
    await screen.findByText('selectAll:{"count":42}');
    expect(api.fetchNotifications).toHaveBeenCalledWith("token", { limit: 20, cursor: null, filter: {}, includeCount: true });
    expect(screen.getByRole("button", { name: "loadMore" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("radio", { name: "filterRead" }));
    await waitFor(() =>
      expect(api.fetchNotifications).toHaveBeenLastCalledWith("token", {
        limit: 20,
        cursor: null,
        filter: { state: "read" },
        includeCount: true,
      }),
    );

    fireEvent.click(screen.getByRole("radio", { name: "category.messages.title" }));
    await waitFor(() =>
      expect(api.fetchNotifications).toHaveBeenLastCalledWith("token", {
        limit: 20,
        cursor: null,
        filter: { state: "read", category: "messages" },
        includeCount: true,
      }),
    );
  });

  it("«Επιλογή όλων (N)» sends the filter, never ids, after the confirm", async () => {
    api.deleteNotifications.mockResolvedValue({ deleted_count: 42 });
    renderCleanup();

    const deleteButton = screen.getByTestId("notification-cleanup-delete");
    expect(deleteButton).toBeDisabled();

    fireEvent.click(await screen.findByTestId("notification-cleanup-select-all"));
    expect(deleteButton).toHaveTextContent('deleteMany:{"count":42}');

    fireEvent.click(deleteButton);
    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getByText('confirmTitle:{"count":42}')).toBeInTheDocument();
    expect(api.deleteNotifications).not.toHaveBeenCalled();

    fireEvent.click(within(dialog).getByTestId("notification-cleanup-confirm"));
    await waitFor(() => expect(api.deleteNotifications).toHaveBeenCalledWith("token", { filter: {} }));
    expect(await screen.findByText('deletedCount:{"count":42}')).toBeInTheDocument();
  });

  it("deletes the rows picked by id, and cancel deletes nothing", async () => {
    api.deleteNotifications.mockResolvedValue({ deleted_count: 1 });
    renderCleanup();

    const [, first] = await screen.findAllByRole("checkbox");
    fireEvent.click(first);
    const deleteButton = screen.getByTestId("notification-cleanup-delete");
    expect(deleteButton).toHaveTextContent('deleteMany:{"count":1}');

    fireEvent.click(deleteButton);
    fireEvent.click(within(await screen.findByRole("dialog")).getByRole("button", { name: "cancel" }));
    expect(api.deleteNotifications).not.toHaveBeenCalled();

    fireEvent.click(deleteButton);
    fireEvent.click(within(await screen.findByRole("dialog")).getByTestId("notification-cleanup-confirm"));
    await waitFor(() => expect(api.deleteNotifications).toHaveBeenCalledWith("token", { ids: ["a"] }));
  });
});
