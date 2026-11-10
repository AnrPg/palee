import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { NotificationRecord } from "@/api/notifications";

const api = vi.hoisted(() => ({
  fetchNotifications: vi.fn(),
  fetchUnreadNotificationCount: vi.fn(),
  deleteNotification: vi.fn(),
  restoreNotification: vi.fn(),
  markNotificationRead: vi.fn(),
  markNotificationClicked: vi.fn(),
  markAllNotificationsRead: vi.fn(),
  deleteNotifications: vi.fn(),
  restoreNotifications: vi.fn(),
  markNotificationsRead: vi.fn(),
}));

vi.mock("@/api/notifications", () => api);

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) => (values ? `${key}:${JSON.stringify(values)}` : key),
  useLocale: () => "en",
}));

vi.mock("next/navigation", () => ({ useRouter: () => ({ push: vi.fn() }) }));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({
    status: "authenticated",
    tokens: { access_token: "token" },
    currentUser: { id: "u1", role: "member" },
  }),
}));

vi.mock("@/hooks/usePushNotifications", () => ({
  usePushNotifications: () => ({ supported: false, enabled: false, refreshCapability: vi.fn() }),
}));
vi.mock("@/lib/realtime", () => ({ subscribeToTopic: () => () => undefined }));
vi.mock("@/lib/membership-role", () => ({ useOrganizationMemberships: () => ({ data: [] }) }));
vi.mock("@/lib/organization-slug", () => ({ useOrganizationSlug: () => null }));
vi.mock("@/components/social/FollowRequestsRow", () => ({ FollowRequestsRow: () => null }));
vi.mock("@/components/notifications/PushDeviceCard", () => ({ PushDeviceCard: () => null }));

import {
  NotificationBell,
  NotificationCard,
  SWIPE_REVEAL_PX,
  UNDO_DELETE_MS,
  openNotifications,
} from "./NotificationBell";

function notification(overrides: Partial<NotificationRecord> = {}): NotificationRecord {
  return {
    id: "n1",
    user_id: "u1",
    organization_id: null,
    type: "booking_approved",
    payload: { url: "/schedule" },
    read_at: null,
    inserted_at: "2026-11-01T10:00:00Z",
    ...overrides,
  };
}

function withClient(node: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={client}>{node}</QueryClientProvider>;
}

function renderCard(overrides: Partial<NotificationRecord> = {}) {
  const handlers = { onClick: vi.fn(), onDelete: vi.fn(), onHide: vi.fn() };
  render(
    withClient(
      <NotificationCard notification={notification(overrides)} targetUrl="/schedule" origin={null} {...handlers} />,
    ),
  );
  return handlers;
}

function swipe(element: Element, fromX: number, toX: number, pointerType = "touch") {
  fireEvent.pointerDown(element, { pointerType, clientX: fromX, clientY: 100 });
  fireEvent.pointerMove(element, { pointerType, clientX: (fromX + toX) / 2, clientY: 100 });
  fireEvent.pointerMove(element, { pointerType, clientX: toX, clientY: 100 });
  fireEvent.pointerUp(element, { pointerType, clientX: toX, clientY: 100 });
  fireEvent.click(element);
}

beforeEach(() => {
  Object.values(api).forEach((mock) => mock.mockReset());
});

afterEach(() => {
  vi.useRealTimers();
});

describe("NotificationCard actions (ADR-460, option B)", () => {
  it("shows trash then closed eye only on hover or focus within, taking no layout space", () => {
    renderCard();
    const actions = screen.getByTestId("notification-actions");

    expect(actions).toHaveClass(
      "absolute",
      "opacity-0",
      "pointer-events-none",
      "group-hover/card:opacity-100",
      "group-hover/card:pointer-events-auto",
      "group-focus-within/card:opacity-100",
      "group-focus-within/card:pointer-events-auto",
      // Touch: always drawn, behind the card, uncovered by the swipe.
      "pointer-coarse:opacity-100",
      "pointer-coarse:z-0",
    );
    expect(screen.getByTestId("notification-card")).toHaveClass("group/card", "relative");

    const buttons = Array.from(actions.querySelectorAll("button"));
    expect(buttons.map((button) => button.getAttribute("aria-label"))).toEqual(["delete", "hide"]);
  });

  it("deletes and hides without opening the notification", () => {
    const handlers = renderCard();

    fireEvent.click(screen.getByRole("button", { name: "delete" }));
    fireEvent.click(screen.getByRole("button", { name: "hide" }));

    expect(handlers.onDelete).toHaveBeenCalledTimes(1);
    expect(handlers.onHide).toHaveBeenCalledTimes(1);
    expect(handlers.onClick).not.toHaveBeenCalled();
  });

  it("offers no hide on a notification already read", () => {
    const handlers = renderCard({ read_at: "2026-11-01T11:00:00Z" });
    const eye = screen.getByRole("button", { name: "alreadyHidden" });

    expect(eye).toHaveAttribute("aria-disabled", "true");
    fireEvent.click(eye);
    expect(handlers.onHide).not.toHaveBeenCalled();
    expect(handlers.onClick).not.toHaveBeenCalled();
  });

  it("reveals the buttons on a swipe to the left, and closes them on a swipe right", () => {
    const handlers = renderCard();
    const wrapper = screen.getByTestId("notification-card");
    const card = wrapper.querySelector("article")!;

    swipe(card, 200, 200 - SWIPE_REVEAL_PX - 10);
    expect(wrapper).toHaveAttribute("data-revealed", "true");
    expect(card.style.transform).toBe(`translateX(-${SWIPE_REVEAL_PX}px)`);
    // The swipe's own click never opens the notification.
    expect(handlers.onClick).not.toHaveBeenCalled();

    swipe(card, 100, 100 + SWIPE_REVEAL_PX);
    expect(wrapper).toHaveAttribute("data-revealed", "false");
    expect(handlers.onClick).not.toHaveBeenCalled();
  });

  it("closes on a tap of the card or elsewhere, and a short swipe springs back", () => {
    const handlers = renderCard();
    const wrapper = screen.getByTestId("notification-card");
    const card = wrapper.querySelector("article")!;

    swipe(card, 200, 180);
    expect(wrapper).toHaveAttribute("data-revealed", "false");

    swipe(card, 200, 50);
    expect(wrapper).toHaveAttribute("data-revealed", "true");
    fireEvent.pointerDown(document.body, { pointerType: "touch" });
    expect(wrapper).toHaveAttribute("data-revealed", "false");

    swipe(card, 200, 50);
    fireEvent.pointerDown(card, { pointerType: "touch", clientX: 120, clientY: 100 });
    fireEvent.pointerUp(card, { pointerType: "touch", clientX: 120, clientY: 100 });
    fireEvent.click(card);
    expect(wrapper).toHaveAttribute("data-revealed", "false");
    expect(handlers.onClick).not.toHaveBeenCalled();

    // An ordinary tap opens it.
    fireEvent.click(card);
    expect(handlers.onClick).toHaveBeenCalledTimes(1);
  });

  it("does not reveal on a mouse drag or a vertical scroll", () => {
    renderCard();
    const wrapper = screen.getByTestId("notification-card");
    const card = wrapper.querySelector("article")!;

    swipe(card, 200, 50, "mouse");
    expect(wrapper).toHaveAttribute("data-revealed", "false");

    fireEvent.pointerDown(card, { pointerType: "touch", clientX: 200, clientY: 100 });
    fireEvent.pointerMove(card, { pointerType: "touch", clientX: 190, clientY: 200 });
    fireEvent.pointerMove(card, { pointerType: "touch", clientX: 50, clientY: 300 });
    fireEvent.pointerUp(card, { pointerType: "touch", clientX: 50, clientY: 300 });
    expect(wrapper).toHaveAttribute("data-revealed", "false");
  });
});

describe("NotificationBell delete with «Αναίρεση» (ADR-460)", () => {
  function page(notifications: NotificationRecord[]) {
    return {
      notifications,
      unread_count: notifications.filter((n) => !n.read_at).length,
      next_cursor: null,
      matching_count: null,
    };
  }

  async function openBell(items: NotificationRecord[]) {
    api.fetchUnreadNotificationCount.mockResolvedValue({ unread_count: items.length });
    api.fetchNotifications.mockResolvedValue(page(items));
    render(withClient(<NotificationBell hideTrigger />));
    act(() => openNotifications());
    await screen.findByText("bookingApproved61fe8f8");
  }

  it("removes the card at once, sends the delete and restores it on «Αναίρεση»", async () => {
    let finishDelete: (value: unknown) => void = () => undefined;
    api.deleteNotification.mockReturnValue(new Promise((resolve) => (finishDelete = resolve)));
    api.restoreNotification.mockResolvedValue({ restored: true });
    await openBell([notification()]);

    fireEvent.click(screen.getByRole("button", { name: "delete" }));

    expect(screen.queryByTestId("notification-card")).not.toBeInTheDocument();
    expect(api.deleteNotification).toHaveBeenCalledWith("token", "n1");
    expect(screen.getByTestId("notification-undo-toast")).toHaveTextContent("deleted");

    fireEvent.click(screen.getByRole("button", { name: "undo" }));
    // The restore waits for the delete to arrive.
    expect(api.restoreNotification).not.toHaveBeenCalled();
    await act(async () => finishDelete({ deleted: true, restorable_for_seconds: 60 }));

    await waitFor(() => expect(api.restoreNotification).toHaveBeenCalledWith("token", "n1"));
    expect(screen.queryByTestId("notification-undo-toast")).not.toBeInTheDocument();
  });

  it("drops «Αναίρεση» after the toast's time", async () => {
    api.deleteNotification.mockResolvedValue({ deleted: true, restorable_for_seconds: 60 });
    await openBell([notification()]);
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });

    fireEvent.click(screen.getByRole("button", { name: "delete" }));
    expect(screen.getByTestId("notification-undo-toast")).toBeInTheDocument();

    act(() => vi.advanceTimersByTime(UNDO_DELETE_MS + 10));
    expect(screen.queryByTestId("notification-undo-toast")).not.toBeInTheDocument();
    expect(api.restoreNotification).not.toHaveBeenCalled();
  });

  it("hides with the closed eye: marked read, moved out of «Νέο»", async () => {
    api.markNotificationRead.mockResolvedValue({ read: true });
    await openBell([notification()]);
    api.fetchNotifications.mockResolvedValue(page([notification({ read_at: "2026-11-01T11:00:00Z" })]));

    fireEvent.click(screen.getByRole("button", { name: "hide" }));

    expect(api.markNotificationRead).toHaveBeenCalledWith("token", "n1");
    // «Διαβασμένες» is collapsed, so the card leaves the view.
    expect(await screen.findByText("youReAllCaughtUp3d39c46")).toBeInTheDocument();
    expect(screen.queryByTestId("notification-card")).not.toBeInTheDocument();
  });
});

describe("NotificationBell stacks of similar notifications (ADR-600)", () => {
  const key = "class_workout_missing:o:box:d:2026-11-10";

  function wodMissing(id: string, overrides: Partial<NotificationRecord> = {}): NotificationRecord {
    return notification({
      id,
      type: "booking_approved",
      group_key: key,
      ...overrides,
    });
  }

  const stackRow = wodMissing("s4", { stack: { key, count: 4, unread_count: 4 } });
  const single = notification({ id: "p1", type: "booking_rejected", stack: null });
  const members = ["s4", "s3", "s2", "s1"].map((id) => wodMissing(id));

  function serve(rows: NotificationRecord[]) {
    api.fetchUnreadNotificationCount.mockResolvedValue({ unread_count: 5 });
    api.fetchNotifications.mockImplementation(async (_token: string, params: { filter?: { group_key?: string } }) =>
      params.filter?.group_key
        ? { notifications: members, unread_count: 5, next_cursor: null, matching_count: null }
        : { notifications: rows, unread_count: 5, next_cursor: null, matching_count: null },
    );
  }

  async function openBell(rows: NotificationRecord[] = [stackRow, single]) {
    serve(rows);
    render(withClient(<NotificationBell hideTrigger />));
    act(() => openNotifications());
    await screen.findByTestId("notification-stack");
  }

  it("asks the server for stacks and shows one as a deck with «+N ακόμη παρόμοιες»", async () => {
    await openBell();

    expect(api.fetchNotifications).toHaveBeenCalledWith("token", expect.objectContaining({ stacks: true }));
    const stack = screen.getByTestId("notification-stack");
    expect(stack).toHaveAttribute("data-stack-count", "4");
    expect(screen.getByTestId("notification-stack-more")).toHaveTextContent('stackMore:{"count":3}');
    expect(screen.getAllByTestId("notification-new-badge")[0]).toHaveTextContent('stackNew:{"count":4}');
    // «Νέο» counts every unread notification, not stacks.
    expect(screen.getByText("5")).toBeInTheDocument();
    expect(screen.getAllByTestId("notification-card")).toHaveLength(2);
  });

  it("opens in place on a tap without marking anything read, and closes again", async () => {
    await openBell();

    fireEvent.click(screen.getByTestId("notification-stack").querySelector("article")!);

    expect(await screen.findByTestId("notification-stack-open")).toHaveTextContent('stackCount:{"count":4}');
    expect(api.fetchNotifications).toHaveBeenCalledWith(
      "token",
      expect.objectContaining({ filter: { group_key: key } }),
    );
    await waitFor(() => expect(screen.getAllByTestId("notification-card")).toHaveLength(5));
    expect(api.markNotificationsRead).not.toHaveBeenCalled();
    expect(api.markNotificationClicked).not.toHaveBeenCalled();

    fireEvent.click(screen.getByTestId("notification-stack-collapse"));
    expect(await screen.findByTestId("notification-stack")).toBeInTheDocument();
  });

  it("the trash deletes the whole stack and «Αναίρεση» restores all of it", async () => {
    api.deleteNotifications.mockResolvedValue({ deleted_count: 4, restorable_for_seconds: 60 });
    api.restoreNotifications.mockResolvedValue({ restored_count: 4 });
    await openBell();

    fireEvent.click(screen.getByRole("button", { name: "stackDelete" }));

    expect(screen.queryByTestId("notification-stack")).not.toBeInTheDocument();
    expect(api.deleteNotifications).toHaveBeenCalledWith("token", { filter: { group_key: key } });
    expect(screen.getByTestId("notification-undo-toast")).toHaveTextContent('deletedCount:{"count":4}');

    fireEvent.click(screen.getByRole("button", { name: "undo" }));
    await waitFor(() => expect(api.restoreNotifications).toHaveBeenCalledWith("token", { group_key: key }));
    expect(api.restoreNotification).not.toHaveBeenCalled();
  });

  it("the closed eye marks the whole stack read", async () => {
    api.markNotificationsRead.mockResolvedValue({ marked_count: 4 });
    await openBell();

    fireEvent.click(screen.getByRole("button", { name: "stackHide" }));

    expect(api.markNotificationsRead).toHaveBeenCalledWith("token", { group_key: key });
    expect(api.markNotificationRead).not.toHaveBeenCalled();
  });

  it("filters a tab on the server", async () => {
    await openBell();

    fireEvent.click(screen.getByRole("radio", { name: "bookings135229c" }));

    await waitFor(() =>
      expect(api.fetchNotifications).toHaveBeenCalledWith(
        "token",
        expect.objectContaining({
          stacks: true,
          filter: { types: expect.arrayContaining(["booking_approved", "class_cancelled"]) },
        }),
      ),
    );
  });
});
