import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";

import { fetchThreadMessages, fetchThreads, getOrCreateContextThread, sendMessage } from "@/api/messaging";
import { BoxMessagePanel } from "./BoxMessagePanel";

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "access" }, currentUser: { id: "owner-1" }, status: "authenticated" }),
}));
vi.mock("@/api/messaging", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/messaging")>()),
  fetchThreads: vi.fn(),
  fetchThreadMessages: vi.fn(),
  getOrCreateContextThread: vi.fn(),
  sendMessage: vi.fn(),
}));

const member = "member-1";
const thread = { id: "t-1", context_type: "box", context_id: member, participants: [] };
const message = (id: string, sender: string, body: string, type = "chat") => ({
  id,
  thread_id: "t-1",
  sender_id: sender,
  body,
  message_type: type,
  topic: null,
  inserted_at: "2026-11-02T09:00:00Z",
});

function renderPanel() {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="en" messages={en}>
        <BoxMessagePanel userId={member} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("«Message from the box» on a member's page", () => {
  it("shows the conversation: the member's messages on one side, every staff message on the box's side", async () => {
    vi.mocked(fetchThreads).mockResolvedValue({ threads: [thread] } as never);
    vi.mocked(fetchThreadMessages).mockResolvedValue({
      messages: [
        message("m-1", member, "Can I freeze my plan?"),
        message("m-2", "owner-1", "Yes, from Monday", "box_message"),
        message("m-3", "desk-2", "Done, frozen", "box_message"),
      ],
    } as never);

    renderPanel();

    const history = await screen.findByTestId("box-message-history");
    const side = (text: string) => within(history).getByText(text).closest("[data-side]")?.getAttribute("data-side");
    expect(side("Can I freeze my plan?")).toBe("other");
    expect(side("Yes, from Monday")).toBe("own");
    expect(side("Done, frozen")).toBe("own");
    expect(screen.getByTestId("box-message-open")).toHaveAttribute("href", "/messages?filter=clubs&thread=t-1");
    expect(getOrCreateContextThread).not.toHaveBeenCalled();
  });

  it("shows no history and creates no thread before the first message", async () => {
    vi.mocked(fetchThreads).mockResolvedValue({ threads: [] } as never);
    renderPanel();

    await waitFor(() => expect(fetchThreads).toHaveBeenCalledWith("access", "box"));
    expect(screen.queryByTestId("box-message-history")).not.toBeInTheDocument();
    expect(screen.queryByTestId("box-message-open")).not.toBeInTheDocument();
    expect(getOrCreateContextThread).not.toHaveBeenCalled();
  });

  it("after sending, the sent message shows in the conversation", async () => {
    let messages = [] as ReturnType<typeof message>[];
    let threads: unknown[] = [];
    vi.mocked(fetchThreads).mockImplementation(async () => ({ threads }) as never);
    vi.mocked(fetchThreadMessages).mockImplementation(async () => ({ messages }) as never);
    vi.mocked(getOrCreateContextThread).mockImplementation(async () => {
      threads = [thread];
      return { thread } as never;
    });
    vi.mocked(sendMessage).mockImplementation(async (_token, _thread, body) => {
      messages = [message("m-9", "owner-1", body, "box_message")];
      return { message: messages[0] } as never;
    });

    renderPanel();
    fireEvent.change(screen.getByLabelText(en.Ui.bmBody), { target: { value: "See you at 18:00" } });
    fireEvent.click(screen.getByRole("button", { name: en.Ui.send9bc2575 }));

    const history = await screen.findByTestId("box-message-history");
    expect(within(history).getByText("See you at 18:00").closest("[data-side]")).toHaveAttribute("data-side", "own");
    expect(screen.getByTestId("box-message-open")).toHaveAttribute("href", "/messages?filter=clubs&thread=t-1");
  });
});
