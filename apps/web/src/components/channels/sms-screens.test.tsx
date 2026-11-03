import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

import { previewClassNotice, recordStaffConsent, saveMyChannels, sendClassNotice, type ClassNotice, type ChannelContact } from "@/api/channels";
import { fetchEventSms } from "@/api/events";

import { AfterBookingSmsAsk } from "./AfterBookingSmsAsk";
import { ClassNoticeDialog } from "./ClassNoticeDialog";
import { ClientSmsPanel } from "./ClientSmsPanel";
import { EventSmsCard } from "./EventSmsCard";

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, currentUser: { id: "me" }, status: "authenticated" }),
}));
vi.mock("@/api/channels", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/channels")>()),
  previewClassNotice: vi.fn(),
  sendClassNotice: vi.fn(),
  lookupChannelContact: vi.fn(),
  recordStaffConsent: vi.fn(),
  saveChannelContact: vi.fn(),
  fetchMyChannels: vi.fn(),
  saveMyChannels: vi.fn(),
}));
const guides = vi.hoisted(() => ({ putGuideProgress: vi.fn(), fetchGuideProgress: vi.fn() }));
vi.mock("@/api/guides", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/guides")>()),
  putGuideProgress: guides.putGuideProgress,
  fetchGuideProgress: guides.fetchGuideProgress,
}));
vi.mock("@/api/events", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/events")>()),
  fetchEventSms: vi.fn(),
}));

const channels = await import("@/api/channels");

function wrap(children: ReactNode) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="Europe/Athens">
        {children}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const notice: ClassNotice = {
  slot_id: "slot-1",
  kind: "cancelled",
  urgent: false,
  participants: 5,
  in_app: 3,
  sms: 1,
  unreachable: 1,
  unreachable_reasons: { no_consent: 1 },
  estimated_cost_cents: 6,
  currency: "EUR",
  budget: { spent_cents: 500, cap_cents: 2000, currency: "EUR" },
  sample: { body: "Box: WOD 18:00 is cancelled.", segments: 1, release_at: "2026-11-02T16:00:00Z", held_for_quiet_hours: false },
  sms_blocked: null,
};

const contact = (consents: ChannelContact["consents"]): ChannelContact => ({ id: "c1", phone: "+30 •••••••678", locale: "el", consents });

beforeEach(() => {
  vi.clearAllMocks();
  guides.fetchGuideProgress.mockResolvedValue({ guides: [] });
  guides.putGuideProgress.mockResolvedValue({ guide_id: "sms_ask_box", status: "dismissed" });
  try {
    window.localStorage.clear();
  } catch {
    // storage may be blocked
  }
});

describe("Update participants (W3 screen 4)", () => {
  it("shows who learns and how, then sends once with one key", async () => {
    vi.mocked(previewClassNotice).mockResolvedValue(notice);
    vi.mocked(sendClassNotice).mockResolvedValue(notice);
    wrap(<ClassNoticeDialog slotId="slot-1" cancelled onClose={() => {}} />);

    expect(await screen.findByTestId("class-notice-sample")).toHaveTextContent("WOD 18:00 is cancelled");
    expect(screen.getByTestId("class-notice-who")).toHaveTextContent("App notification");
    const send = screen.getByTestId("class-notice-send");
    expect(send).toHaveTextContent("Notify 4 people");
    fireEvent.click(send);

    await waitFor(() => expect(sendClassNotice).toHaveBeenCalledTimes(1));
    const request = vi.mocked(sendClassNotice).mock.calls[0][1];
    expect(request).toMatchObject({ slot_id: "slot-1", kind: "cancelled" });
    expect(request.idempotency_key).toBeTruthy();
    expect(await screen.findByRole("button", { name: "Done" })).toBeInTheDocument();
  });

  it("asks for the text of a free notice and says plainly when SMS cannot leave", async () => {
    vi.mocked(previewClassNotice).mockResolvedValue({ ...notice, kind: "free", sms: 0, sms_blocked: "channels_demo_mode" });
    wrap(<ClassNoticeDialog slotId="slot-1" cancelled={false} onClose={() => {}} />);

    fireEvent.click(await screen.findByRole("radio", { name: "Own text" }));
    expect(screen.getByTestId("class-notice-send")).toBeDisabled();
    fireEvent.change(screen.getByLabelText("Message"), { target: { value: "Bring a towel" } });

    expect(await screen.findByTestId("class-notice-blocked")).toHaveTextContent(en.Sms.errors.channels_demo_mode);
    await waitFor(() => expect(previewClassNotice).toHaveBeenLastCalledWith("access", expect.objectContaining({ kind: "free", text: "Bring a towel" })));
  });
});

describe("Event SMS card (W3 screen 6 B and C)", () => {
  it("counts who gets SMS and switches SMS off for the event", async () => {
    vi.mocked(fetchEventSms).mockResolvedValue({
      enabled: true,
      connected: true,
      going: 40,
      recipients: 12,
      spent_cents: 18,
      per_message_cents: 6,
      currency: "EUR",
    } as Awaited<ReturnType<typeof fetchEventSms>>);
    const onSwitch = vi.fn().mockResolvedValue({});
    wrap(<EventSmsCard eventId="ev-1" onSwitch={onSwitch} />);

    expect(await screen.findByTestId("event-sms-count")).toHaveTextContent("12 of 40 will get SMS");
    fireEvent.click(screen.getByRole("switch", { name: "SMS for this event" }));
    await waitFor(() => expect(onSwitch).toHaveBeenCalledWith(false));
  });

  it("shows nothing while the organiser sends no SMS", async () => {
    vi.mocked(fetchEventSms).mockResolvedValue({
      enabled: true,
      connected: false,
      going: 3,
      recipients: 0,
      spent_cents: 0,
      per_message_cents: 0,
      currency: "EUR",
    } as Awaited<ReturnType<typeof fetchEventSms>>);
    const { container } = wrap(<EventSmsCard eventId="ev-2" onSwitch={vi.fn()} />);
    await waitFor(() => expect(fetchEventSms).toHaveBeenCalled());
    expect(container.querySelector("[data-testid=event-sms]")).toBeNull();
  });
});

describe("Client card SMS (W3 screen 2 C)", () => {
  it("records a desk consent only after the client said yes", async () => {
    vi.mocked(channels.lookupChannelContact).mockResolvedValue({ contact: contact([]) });
    vi.mocked(recordStaffConsent).mockResolvedValue({ contact: contact([{ channel: "sms", purpose: "service", granted: true, source: "staff" }]) });
    wrap(<ClientSmsPanel userId="u1" />);

    expect(await screen.findByText("+30 •••••••678")).toBeInTheDocument();
    fireEvent.click(screen.getAllByRole("button", { name: "Said it at the desk" })[0]);
    const record = screen.getByRole("button", { name: "Record" });
    expect(record).toBeDisabled();
    fireEvent.click(screen.getByRole("checkbox"));
    fireEvent.click(record);

    await waitFor(() => expect(recordStaffConsent).toHaveBeenCalledWith("access", "c1", "service", true));
  });
});

describe("Ask once after a booking (W3 screen 2 B)", () => {
  it("never asks again on this device after «Not now»", async () => {
    vi.mocked(channels.fetchMyChannels).mockResolvedValue({ channels: ["sms"], contact: null });
    const onDone = vi.fn();
    const first = wrap(<AfterBookingSmsAsk slug="box" onDone={onDone} />);

    fireEvent.click(await screen.findByRole("button", { name: "Not now" }));
    expect(onDone).toHaveBeenCalled();
    // Kept with the account too, so another device never asks again.
    expect(guides.putGuideProgress).toHaveBeenCalledWith("access", "sms_ask_box", { status: "dismissed", step: 0, version: 1 });
    first.unmount();

    const second = wrap(<AfterBookingSmsAsk slug="box" onDone={onDone} />);
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(second.container.querySelector("[data-testid=after-booking-sms]")).toBeNull();
    expect(screen.queryByText(en.Sms.askTitle)).toBeNull();
  });

  it("saves the mobile with the Updates consent only", async () => {
    vi.mocked(channels.fetchMyChannels).mockResolvedValue({ channels: ["sms"], contact: null });
    vi.mocked(saveMyChannels).mockResolvedValue({ channels: ["sms"], contact: contact([{ channel: "sms", purpose: "service", granted: true }]) });
    const onDone = vi.fn();
    wrap(<AfterBookingSmsAsk slug="box" onDone={onDone} />);

    fireEvent.change(await screen.findByLabelText("Mobile for messages"), { target: { value: "6912345678" } });
    fireEvent.click(screen.getByRole("button", { name: "Yes, text me" }));

    await waitFor(() => expect(saveMyChannels).toHaveBeenCalled());
    const update = vi.mocked(saveMyChannels).mock.calls[0][2];
    expect(update.phone).toBe("6912345678");
    expect(update.consents).toEqual([{ channel: "sms", purpose: "service", granted: true }]);
    await waitFor(() => expect(onDone).toHaveBeenCalled());
  });

  it("is not asked again after «Όχι τώρα» on another device", async () => {
    guides.fetchGuideProgress.mockResolvedValue({ guides: [{ guide_id: "sms_ask_box3", status: "dismissed" }] });
    vi.mocked(channels.fetchMyChannels).mockResolvedValue({ channels: ["sms"], contact: null });
    const { container } = wrap(<AfterBookingSmsAsk slug="box3" onDone={vi.fn()} />);
    await waitFor(() => expect(guides.fetchGuideProgress).toHaveBeenCalled());
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(container.querySelector("[data-testid=after-booking-sms]")).toBeNull();
    expect(channels.fetchMyChannels).not.toHaveBeenCalled();
  });

  it("is not asked where the box sends no SMS", async () => {
    vi.mocked(channels.fetchMyChannels).mockResolvedValue({ channels: [], contact: null });
    const { container } = wrap(<AfterBookingSmsAsk slug="box2" onDone={vi.fn()} />);
    await waitFor(() => expect(channels.fetchMyChannels).toHaveBeenCalled());
    expect(container.querySelector("[data-testid=after-booking-sms]")).toBeNull();
  });
});
